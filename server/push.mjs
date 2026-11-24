import { createHash, ECDH } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import webPush from 'web-push';

const minute = 60_000;
const maxSubscriptionsPerAccount = 8;
const retryDelays = [5 * minute, 15 * minute];
const maxAttempts = retryDelays.length + 1;
const staleDeliveryAge = 31 * 24 * 60 * minute;
const maxJobsPerTick = 128;

export function validPushEndpoint(value) {
  if (typeof value !== 'string' || value.length > 4096) return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.href !== value || url.protocol !== 'https:' || url.username ||
      url.password || url.port || url.hash) return false;

  const { hostname, pathname, search } = url;
  if (hostname === 'fcm.googleapis.com' || hostname === 'android.googleapis.com') {
    return !search && /^\/fcm\/send\/[A-Za-z0-9._~:-]+$/.test(pathname);
  }
  if (hostname === 'updates.push.services.mozilla.com' ||
      hostname === 'push.services.mozilla.com') {
    return !search && /^\/wpush\/v[12]\/[A-Za-z0-9._~-]+$/.test(pathname);
  }
  if (/^[a-z0-9-]+\.push\.apple\.com$/.test(hostname)) {
    return !search && /^\/[A-Za-z0-9._~-]{20,}$/.test(pathname);
  }
  if (/^[a-z0-9-]+\.notify\.windows\.com$/.test(hostname)) {
    return /^\/w\/?$/.test(pathname) && /^\?token=[A-Za-z0-9._~%+=/-]+$/.test(search);
  }
  return false;
}

function decodeKey(value, byteLength) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+={0,2}$/.test(value)) return null;
  const decoded = Buffer.from(value, 'base64url');
  return decoded.length === byteLength &&
    decoded.toString('base64url') === value.replace(/=+$/, '') ? decoded : null;
}

function normalizeSubscription(subscription) {
  if (!validPushEndpoint(subscription?.endpoint)) return null;
  const p256dh = decodeKey(subscription.keys?.p256dh, 65);
  const auth = decodeKey(subscription.keys?.auth, 16);
  if (p256dh?.[0] !== 4 || !auth) return null;
  try {
    ECDH.convertKey(p256dh, 'prime256v1');
  } catch {
    return null;
  }
  return {
    endpoint: subscription.endpoint,
    keys: { p256dh: p256dh.toString('base64url'), auth: auth.toString('base64url') },
  };
}

function timeFormatter(timezone) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
}

function normalizeTimezone(value) {
  if (typeof value !== 'string' || value.length > 64 ||
      !/^[A-Za-z][A-Za-z0-9_.+-]*(?:\/[A-Za-z0-9_.+-]+)*$/.test(value)) return null;
  try {
    return timeFormatter(value).resolvedOptions().timeZone;
  } catch {
    return null;
  }
}

function localTime(formatter, now) {
  const parts = Object.fromEntries(formatter.formatToParts(now).map(({ type, value }) => [type, value]));
  return {
    day: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

function topicFor(eventKey) {
  return createHash('sha256').update(eventKey).digest('base64url').slice(0, 32);
}

function pushTransport(subject, keys) {
  return (subscription, message, { ttl, topic }) => {
    const isWns = new URL(subscription.endpoint).hostname.endsWith('.notify.windows.com');
    return webPush.sendNotification(subscription, JSON.stringify(message), {
      vapidDetails: { subject, ...keys },
      contentEncoding: 'aes128gcm',
      TTL: ttl,
      urgency: 'high',
      topic,
      timeout: 8000,
      ...(isWns && {
        headers: { 'X-WNS-Type': 'wns/raw', 'X-WNS-TTL': ttl },
      }),
    });
  };
}

function subscriptionFrom(row) {
  return { endpoint: row.endpoint, keys: { p256dh: row.p256dh, auth: row.auth } };
}

export function openPushService({
  filename,
  subject,
  reminderEvents,
  clock = Date.now,
  transport,
  onError = () => {},
}) {
  const db = new DatabaseSync(filename);
  try {
    db.exec(`
      PRAGMA busy_timeout = 5000;
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS push_vapid (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        public_key TEXT NOT NULL,
        private_key TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS push_subscriptions (
        endpoint TEXT PRIMARY KEY,
        account_id INTEGER NOT NULL REFERENCES account(id),
        p256dh TEXT NOT NULL,
        auth TEXT NOT NULL,
        timezone TEXT NOT NULL,
        last_test_at INTEGER
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS push_account ON push_subscriptions(account_id);
      CREATE TABLE IF NOT EXISTS push_deliveries (
        endpoint TEXT NOT NULL REFERENCES push_subscriptions(endpoint) ON DELETE CASCADE,
        event_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL,
        retry_at INTEGER,
        PRIMARY KEY(endpoint, event_key)
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS push_delivery_age ON push_deliveries(created_at);
    `);
    const selectKeys = db.prepare(
      'SELECT public_key AS publicKey, private_key AS privateKey FROM push_vapid WHERE id = 1',
    );
    let keys = selectKeys.get();
    if (!keys) {
      const generated = webPush.generateVAPIDKeys();
      db.prepare('INSERT OR IGNORE INTO push_vapid VALUES (1, ?, ?)').run(
        generated.publicKey, generated.privateKey,
      );
      keys = selectKeys.get();
    }
    return createPushService({
      db, publicKey: keys.publicKey, reminderEvents, clock,
      sendPush: transport ?? pushTransport(subject, keys), onError,
    });
  } catch (error) {
    db.close();
    throw error;
  }
}

function createPushService({ db, publicKey, reminderEvents, clock, sendPush, onError }) {
  const find = db.prepare('SELECT * FROM push_subscriptions WHERE endpoint = ?');
  const subscriptions = db.prepare('SELECT * FROM push_subscriptions ORDER BY endpoint');
  const put = db.prepare(`
    INSERT INTO push_subscriptions (account_id, endpoint, p256dh, auth, timezone)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(endpoint) DO UPDATE SET p256dh = excluded.p256dh, auth = excluded.auth,
      timezone = excluded.timezone WHERE push_subscriptions.account_id = excluded.account_id
  `);
  const count = db.prepare('SELECT count(*) AS count FROM push_subscriptions WHERE account_id = ?');
  const remove = db.prepare('DELETE FROM push_subscriptions WHERE account_id = ? AND endpoint = ?');
  const removeExpired = db.prepare(`
    DELETE FROM push_subscriptions WHERE endpoint = ? AND account_id = ? AND p256dh = ? AND auth = ?
  `);
  const claimTest = db.prepare(`
    UPDATE push_subscriptions SET last_test_at = ?
    WHERE account_id = ? AND endpoint = ? AND (last_test_at IS NULL OR last_test_at <= ?)
  `);
  const getLedger = db.prepare('SELECT snapshot, revision FROM ledger WHERE id = ?');
  const getRevision = db.prepare('SELECT revision FROM ledger WHERE id = ?');
  const getDelivery = db.prepare(`
    SELECT attempts, retry_at FROM push_deliveries WHERE endpoint = ? AND event_key = ?
  `);
  const claimDelivery = db.prepare(`
    INSERT INTO push_deliveries (endpoint, event_key, created_at, attempts, retry_at)
    VALUES (?, ?, ?, 1, ?)
    ON CONFLICT(endpoint, event_key) DO UPDATE SET attempts = push_deliveries.attempts + 1,
      retry_at = excluded.retry_at
    WHERE push_deliveries.attempts < ? AND push_deliveries.retry_at <= excluded.created_at
    RETURNING attempts
  `);
  const completeDelivery = db.prepare(`
    UPDATE push_deliveries SET retry_at = ? WHERE endpoint = ? AND event_key = ?
  `);
  const purgeDeliveries = db.prepare('DELETE FROM push_deliveries WHERE created_at < ?');
  let schedules = new Map();
  let running;
  let closing = false;

  function removeIfExpired(row, error) {
    if (error?.statusCode !== 404 && error?.statusCode !== 410) return false;
    removeExpired.run(row.endpoint, row.account_id, row.p256dh, row.auth);
    return true;
  }

  async function deliver(job) {
    const { row, key, title, body, day, formatter, revision } = job;
    const now = clock();
    const currentTime = localTime(formatter, now);
    if (currentTime.day !== day || getRevision.get(row.account_id)?.revision !== revision) return;
    const current = find.get(row.endpoint);
    if (!current || row.account_id !== current.account_id || row.p256dh !== current.p256dh ||
        row.auth !== current.auth || row.timezone !== current.timezone) return;

    // Store the claim before sending. The lease allows a later tick to recover
    // after a crash, while the stable Push Topic and notification tag coalesce retries.
    const claimed = claimDelivery.get(row.endpoint, key, now, now + 2 * minute, maxAttempts);
    if (!claimed) return;
    const topic = topicFor(key);
    try {
      await sendPush(subscriptionFrom(row), { title, body, tag: topic }, {
        ttl: Math.min(6 * 60 * 60, (24 * 60 - currentTime.minutes) * 60), topic,
      });
      completeDelivery.run(null, row.endpoint, key);
    } catch (error) {
      if (removeIfExpired(row, error)) return;
      const status = error?.statusCode;
      const retryable = status === undefined || status === 429 || status >= 500;
      const retryAt = retryable && claimed.attempts < maxAttempts
        ? clock() + retryDelays[claimed.attempts - 1] : null;
      completeDelivery.run(retryAt, row.endpoint, key);
      onError('push_delivery_failed', status);
    }
  }

  async function inspectDue() {
    const now = clock();
    purgeDeliveries.run(now - staleDeliveryAge);
    const dates = new Map();
    const currentSchedules = new Map();
    const jobs = [];
    for (const row of subscriptions.all()) {
      if (!dates.has(row.timezone)) {
        const formatter = timeFormatter(row.timezone);
        dates.set(row.timezone, { ...localTime(formatter, now), formatter });
      }
      const { day, minutes, formatter } = dates.get(row.timezone);
      if (minutes < 9 * 60) continue;
      const scheduleKey = `${row.account_id}:${day}`;
      if (!currentSchedules.has(scheduleKey)) {
        const previous = schedules.get(scheduleKey);
        const revision = getRevision.get(row.account_id)?.revision;
        if (previous && previous.revision === revision) {
          currentSchedules.set(scheduleKey, previous);
        } else {
          const ledger = getLedger.get(row.account_id);
          currentSchedules.set(scheduleKey, {
            revision: ledger?.revision,
            events: ledger?.snapshot ? reminderEvents(JSON.parse(ledger.snapshot), day) : [],
          });
        }
      }
      const { revision, events } = currentSchedules.get(scheduleKey);
      for (const event of events) {
        const delivery = getDelivery.get(row.endpoint, event.key);
        if (delivery && (delivery.retry_at === null || delivery.retry_at > now ||
            delivery.attempts >= maxAttempts)) continue;
        jobs.push({ ...event, row, day, formatter, revision });
        if (jobs.length === maxJobsPerTick) break;
      }
      if (jobs.length === maxJobsPerTick) break;
    }
    schedules = currentSchedules;

    const workers = Math.min(jobs.length, 4);
    await Promise.all(Array.from({ length: workers }, async (_, worker) => {
      for (let index = worker; index < jobs.length && !closing; index += workers) {
        await deliver(jobs[index]);
      }
    }));
  }

  return {
    publicKey,
    subscribe(accountId, payload) {
      const subscription = normalizeSubscription(payload?.subscription);
      if (!subscription) return { error: 'invalid_push_subscription', status: 400 };
      const timezone = normalizeTimezone(payload?.timezone);
      if (!timezone) return { error: 'invalid_timezone', status: 400 };
      const current = find.get(subscription.endpoint);
      if (!current && count.get(accountId).count >= maxSubscriptionsPerAccount) {
        return { error: 'push_subscription_limit', status: 409 };
      }
      const result = put.run(
        accountId, subscription.endpoint, subscription.keys.p256dh, subscription.keys.auth, timezone,
      );
      return result.changes ? {} : { error: 'push_subscription_in_use', status: 409 };
    },
    unsubscribe(accountId, endpoint) {
      if (!validPushEndpoint(endpoint)) return { error: 'invalid_push_endpoint', status: 400 };
      const row = find.get(endpoint);
      if (row && String(row.account_id) !== accountId) {
        return { error: 'push_subscription_not_found', status: 404 };
      }
      remove.run(accountId, endpoint);
      return {};
    },
    async test(accountId, endpoint) {
      if (!validPushEndpoint(endpoint)) return { error: 'invalid_push_endpoint', status: 400 };
      const row = find.get(endpoint);
      if (!row || String(row.account_id) !== accountId) {
        return { error: 'push_subscription_not_found', status: 404 };
      }
      const now = clock();
      if (!claimTest.run(now, accountId, endpoint, now - minute).changes) {
        return { error: 'push_test_rate_limit', status: 429 };
      }
      try {
        await sendPush(subscriptionFrom(row), {
          title: 'Finance Compass',
          body: '财务提醒测试。此设备已能接收系统通知。',
          tag: 'finance-compass-test',
        }, { ttl: 60, topic: 'finance-compass-test' });
        return {};
      } catch (error) {
        if (removeIfExpired(row, error)) return { error: 'push_subscription_expired', status: 410 };
        onError('push_test_failed', error?.statusCode);
        return { error: 'push_delivery_failed', status: 502 };
      }
    },
    runDue() {
      if (closing) return Promise.resolve();
      running ??= inspectDue().finally(() => { running = undefined; });
      return running;
    },
    async close() {
      closing = true;
      try {
        await running;
      } finally {
        db.close();
      }
    },
  };
}
