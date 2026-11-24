import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { promisify } from 'node:util';

const derivePassword = promisify(scrypt);
const scryptOptions = { N: 131072, r: 8, p: 1, maxmem: 160 * 1024 * 1024 };
const dummySalt = randomBytes(16);
const dummyDigest = randomBytes(32);
const schemaVersion = 1;
export const sessionLifetime = 7 * 24 * 60 * 60;

export function databasePath() {
  return process.env.FINANCE_SYNC_DB || '/data/finance-sync.sqlite3';
}

export function usernameValid(username) {
  return typeof username === 'string' && /^[a-zA-Z0-9._-]{1,64}$/.test(username);
}

export function passwordValid(password) {
  return typeof password === 'string' &&
    Buffer.byteLength(password, 'utf8') >= 12 &&
    Buffer.byteLength(password, 'utf8') <= 256;
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function transaction(database, mode, action) {
  database.exec(mode);
  try {
    const result = action();
    database.exec('COMMIT');
    return result;
  } catch (error) {
    database.exec('ROLLBACK');
    throw error;
  }
}

function migrate(database) {
  transaction(database, 'BEGIN IMMEDIATE', () => {
    const { user_version: version } = database.prepare('PRAGMA user_version').get();
    if (version === schemaVersion) return;
    if (version !== 0) throw new Error('Unsupported sync database schema version.');
    const legacy = database.prepare(
      "SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'account'",
    ).get();
    if (legacy) {
      database.exec(`
        ALTER TABLE account RENAME TO legacy_account;
        ALTER TABLE sessions RENAME TO legacy_sessions;
        ALTER TABLE ledger RENAME TO legacy_ledger;
        ALTER TABLE operations RENAME TO legacy_operations;
      `);
    }
    database.exec(`
      CREATE TABLE account (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        salt BLOB NOT NULL,
        digest BLOB NOT NULL
      );
      CREATE TABLE sessions (
        token_hash TEXT PRIMARY KEY,
        account_id INTEGER NOT NULL REFERENCES account(id),
        expires INTEGER NOT NULL
      ) WITHOUT ROWID;
      CREATE INDEX sessions_account ON sessions(account_id);
      CREATE INDEX sessions_expires ON sessions(expires);
      CREATE TABLE ledger (
        id INTEGER PRIMARY KEY REFERENCES account(id),
        revision INTEGER NOT NULL DEFAULT 0,
        snapshot TEXT
      );
      CREATE TABLE operations (
        account_id INTEGER NOT NULL REFERENCES account(id),
        id TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        revision INTEGER NOT NULL,
        PRIMARY KEY (account_id, id)
      ) WITHOUT ROWID;
    `);
    if (legacy) {
      const owner = database.prepare('SELECT id FROM legacy_account WHERE id = 1').get();
      if (owner) {
        database.exec(`
          INSERT INTO account SELECT id, username, salt, digest FROM legacy_account;
          INSERT INTO ledger SELECT id, revision, snapshot FROM legacy_ledger;
          INSERT INTO sessions SELECT token_hash, 1, expires FROM legacy_sessions;
          INSERT INTO operations SELECT 1, id, fingerprint, revision FROM legacy_operations;
        `);
        if (!database.prepare('SELECT 1 FROM ledger WHERE id = 1').get()) {
          throw new Error('The previous account is missing its ledger.');
        }
      } else {
        const hasOwnerlessData = database.prepare(`
          SELECT EXISTS(SELECT 1 FROM legacy_ledger WHERE revision != 0 OR snapshot IS NOT NULL)
            OR EXISTS(SELECT 1 FROM legacy_sessions)
            OR EXISTS(SELECT 1 FROM legacy_operations) AS found
        `).get().found;
        if (hasOwnerlessData) throw new Error('The previous ledger data has no account.');
      }
      database.exec(`
        DROP TABLE legacy_operations;
        DROP TABLE legacy_sessions;
        DROP TABLE legacy_ledger;
        DROP TABLE legacy_account;
      `);
    }
    database.exec(`PRAGMA user_version = ${schemaVersion}`);
  });
}

export function openStore(filename = databasePath(), { maxAccounts = 128 } = {}) {
  if (filename !== ':memory:') mkdirSync(dirname(filename), { recursive: true, mode: 0o700 });
  const database = new DatabaseSync(filename);
  try {
    database.exec(`
      PRAGMA busy_timeout = 5000;
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      PRAGMA foreign_keys = ON;
    `);
    migrate(database);
  } catch (error) {
    database.close();
    throw error;
  }

  const writeTransaction = (action) => transaction(database, 'BEGIN IMMEDIATE', action);
  const account = database.prepare(
    'SELECT CAST(id AS TEXT) AS accountId, salt, digest FROM account WHERE username = ?',
  );
  const countAccounts = database.prepare('SELECT count(*) AS count FROM account');
  const insertAccount = database.prepare(
    'INSERT INTO account (username, salt, digest) VALUES (?, ?, ?) RETURNING CAST(id AS TEXT) AS accountId',
  );
  const updatePassword = database.prepare('UPDATE account SET salt = ?, digest = ? WHERE id = ?');
  const createLedger = database.prepare('INSERT INTO ledger (id) VALUES (?)');
  const readLedger = database.prepare('SELECT revision, snapshot FROM ledger WHERE id = ?');
  const readRevision = database.prepare('SELECT revision FROM ledger WHERE id = ?');
  const updateLedger = database.prepare(
    'UPDATE ledger SET revision = ?, snapshot = ? WHERE id = ? AND revision = ?',
  );
  const readOperation = database.prepare(
    'SELECT fingerprint, revision FROM operations WHERE account_id = ? AND id = ?',
  );
  const recordOperation = database.prepare(
    'INSERT INTO operations (account_id, id, fingerprint, revision) VALUES (?, ?, ?, ?)',
  );
  const createSession = database.prepare('INSERT INTO sessions (token_hash, account_id, expires) VALUES (?, ?, ?)');
  const readSession = database.prepare(`
    SELECT CAST(account.id AS TEXT) AS accountId, account.username
    FROM sessions JOIN account ON account.id = sessions.account_id
    WHERE token_hash = ? AND expires > ?
  `);
  const purgeSessions = database.prepare('DELETE FROM sessions WHERE expires <= ?');
  const deleteSession = database.prepare('DELETE FROM sessions WHERE token_hash = ?');
  const revokeAccountSessions = database.prepare('DELETE FROM sessions WHERE account_id = ?');
  const clock = () => Math.floor(Date.now() / 1000);

  function startSession(accountId) {
    const token = randomBytes(32).toString('base64url');
    const now = clock();
    purgeSessions.run(now);
    createSession.run(sha256(token), accountId, now + sessionLifetime);
    return token;
  }

  function sessionFor(token) {
    return token ? readSession.get(sha256(token), clock()) : undefined;
  }

  function readOwnedLedger(token, expectedAccountId, select) {
    return transaction(database, 'BEGIN', () => {
      const current = sessionFor(token);
      if (!current) return { error: 'unauthorized' };
      if (expectedAccountId !== undefined && expectedAccountId !== current.accountId) {
        return { error: 'account_changed' };
      }
      return { ...current, ...select.get(current.accountId) };
    });
  }

  return {
    async provision(username, password) {
      if (!usernameValid(username) || !passwordValid(password)) {
        throw new Error('Use a username with 1–64 ASCII letters, digits, dots, hyphens or underscores and a password of 12–256 UTF-8 bytes.');
      }
      const salt = randomBytes(16);
      const digest = await derivePassword(password, salt, 32, scryptOptions);
      writeTransaction(() => {
        const saved = account.get(username);
        if (saved) {
          updatePassword.run(salt, digest, saved.accountId);
          revokeAccountSessions.run(saved.accountId);
          return;
        }
        const created = insertAccount.get(username, salt, digest);
        createLedger.run(created.accountId);
      });
    },

    async register(username, password) {
      if (!usernameValid(username) || !passwordValid(password)) return { error: 'invalid_credentials' };
      if (account.get(username)) return { error: 'username_taken' };
      if (countAccounts.get().count >= maxAccounts) return { error: 'registration_unavailable' };
      const salt = randomBytes(16);
      const digest = await derivePassword(password, salt, 32, scryptOptions);
      return writeTransaction(() => {
        if (account.get(username)) return { error: 'username_taken' };
        if (countAccounts.get().count >= maxAccounts) return { error: 'registration_unavailable' };
        const { accountId } = insertAccount.get(username, salt, digest);
        createLedger.run(accountId);
        return { token: startSession(accountId) };
      });
    },

    async login(username, password, expectedAccountId) {
      const saved = account.get(username);
      const digest = await derivePassword(password, saved?.salt ?? dummySalt, 32, scryptOptions);
      if (!timingSafeEqual(digest, saved?.digest ?? dummyDigest) || !saved) {
        return { error: 'invalid_credentials' };
      }
      return writeTransaction(() => {
        const current = account.get(username);
        if (!current || !timingSafeEqual(current.digest, digest) || current.accountId !== saved.accountId) {
          return { error: 'invalid_credentials' };
        }
        if (expectedAccountId !== undefined && expectedAccountId !== current.accountId) {
          return { error: 'account_changed' };
        }
        return { token: startSession(current.accountId) };
      });
    },

    logout(token, expectedAccountId) {
      return writeTransaction(() => {
        const current = sessionFor(token);
        if (!current) return {};
        if (expectedAccountId !== undefined && expectedAccountId !== current.accountId) {
          return { error: 'account_changed' };
        }
        deleteSession.run(sha256(token));
        return {};
      });
    },

    readLedger(token, expectedAccountId) {
      const row = readOwnedLedger(token, expectedAccountId, readLedger);
      if (row.error || row.snapshot === null) return row;
      return { ...row, snapshot: JSON.parse(row.snapshot) };
    },

    readLedgerRevision(token, expectedAccountId) {
      return readOwnedLedger(token, expectedAccountId, readRevision);
    },

    authorize(token, expectedAccountId) {
      const current = sessionFor(token);
      if (!current) return { error: 'unauthorized' };
      if (expectedAccountId !== current.accountId) return { error: 'account_changed' };
      return {};
    },

    writeLedger(token, expectedAccountId, { baseRevision, operationId, snapshot }) {
      const encoded = JSON.stringify(snapshot);
      const fingerprint = sha256(`${baseRevision}:${encoded}`);
      return writeTransaction(() => {
        const current = sessionFor(token);
        if (!current) return { error: 'unauthorized' };
        const { accountId } = current;
        if (expectedAccountId !== accountId) return { error: 'account_changed' };
        const previous = readOperation.get(accountId, operationId);
        if (previous) {
          return previous.fingerprint === fingerprint
            ? { revision: previous.revision }
            : { error: 'operation_reused' };
        }
        const revision = baseRevision + 1;
        const updated = updateLedger.run(revision, encoded, accountId, baseRevision);
        if (updated.changes !== 1) {
          return { error: 'revision_conflict', revision: readLedger.get(accountId).revision };
        }
        recordOperation.run(accountId, operationId, fingerprint, revision);
        return { revision };
      });
    },

    close() {
      database.close();
    },
  };
}
