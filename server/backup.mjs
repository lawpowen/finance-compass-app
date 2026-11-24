import { closeSync, mkdirSync, openSync, unlinkSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { backup, DatabaseSync } from 'node:sqlite';
import { databasePath } from './store.mjs';

process.umask(0o077);
const filename = process.argv[2];
if (process.argv.length !== 3) {
  console.error('Usage: node server/backup.mjs <new-backup-path>');
  process.exitCode = 1;
} else {
  const destination = resolve(filename);
  let targetCreated = false;
  let source;
  try {
    source = new DatabaseSync(databasePath(), { readOnly: true });
    mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
    closeSync(openSync(destination, 'wx', 0o600));
    targetCreated = true;
    await backup(source, destination);
    const check = new DatabaseSync(destination, { readOnly: true });
    try {
      if (check.prepare('PRAGMA quick_check').get().quick_check !== 'ok') {
        throw new Error('SQLite backup failed its integrity check.');
      }
    } finally {
      check.close();
    }
    console.info('Finance sync backup verified.');
  } catch (error) {
    if (targetCreated) unlinkSync(destination);
    console.error('Backup failed:', error.message);
    process.exitCode = 1;
  } finally {
    source?.close();
  }
}
