// Flutter 3.44 only emits a self-unregistering flutter_service_worker.js stub,
// and web/flutter_bootstrap.js never registers it. This shell worker caches
// static application files only; ledger API requests always use the network.
if ('serviceWorker' in navigator) {
  const serviceWorkers = navigator.serviceWorker;
  let pageWorker = serviceWorkers.controller;
  let registration;
  let installedUpdate;
  let applyingUpdate;
  window.financeCompassUpdateReady = false;

  function announceUpdate(worker) {
    installedUpdate = worker;
    if (window.financeCompassUpdateReady) return;
    window.financeCompassUpdateReady = true;
    window.dispatchEvent(new Event('finance-compass-update-ready'));
  }

  serviceWorkers.addEventListener('controllerchange', () => {
    const active = serviceWorkers.controller;
    if (!active) return;
    if (!pageWorker) {
      // Initial installation changes the controller without an update.
      pageWorker = active;
    } else if (active !== pageWorker) {
      // A different tab can activate the update. Keep this tab open until
      // its own user confirms the reload.
      announceUpdate(active);
    }
  });

  window.financeCompassApplyUpdate = () => {
    if (applyingUpdate) return applyingUpdate;
    if (!window.financeCompassUpdateReady) {
      return Promise.reject(new Error('No update is available'));
    }
    applyingUpdate = (async () => {
      const active = serviceWorkers.controller;
      if (!active || active === pageWorker) {
        const waiting = registration?.waiting ?? installedUpdate;
        if (waiting?.state !== 'installed') throw new Error('Update is not waiting');
        await new Promise((resolve, reject) => {
          const finish = (error) => {
            serviceWorkers.removeEventListener('controllerchange', checkController);
            window.clearTimeout(timer);
            if (error) reject(error);
            else resolve();
          };
          const checkController = () => {
            if (serviceWorkers.controller && serviceWorkers.controller !== pageWorker) finish();
          };
          const timer = window.setTimeout(() => finish(new Error('Update activation timed out')), 15_000);
          serviceWorkers.addEventListener('controllerchange', checkController);
          try {
            waiting.postMessage({ type: 'finance-compass-activate-update' });
            checkController();
          } catch (error) {
            finish(error);
          }
        });
      }
      window.location.reload();
    })().finally(() => { applyingUpdate = undefined; });
    return applyingUpdate;
  };

  function watchInstallation(worker) {
    if (!worker) return;
    const checkState = () => {
      if (worker.state === 'installed' && serviceWorkers.controller &&
          worker !== serviceWorkers.controller) announceUpdate(worker);
    };
    worker.addEventListener('statechange', checkState);
    checkState();
  }

  function registerWorker() {
    serviceWorkers.register('service-worker.js', { updateViaCache: 'none' })
      .then((currentRegistration) => {
        registration = currentRegistration;
        registration.addEventListener('updatefound', () => watchInstallation(registration.installing));
        watchInstallation(registration.waiting ?? registration.installing);
        let lastCheck = Date.now();
        const checkForUpdate = () => {
          const now = Date.now();
          if (document.visibilityState !== 'visible' || now - lastCheck < 60_000) return;
          lastCheck = now;
          registration.update().catch(() => {});
        };
        document.addEventListener('visibilitychange', checkForUpdate);
        window.addEventListener('pageshow', checkForUpdate);
        window.addEventListener('online', checkForUpdate);
        window.setInterval(checkForUpdate, 60_000);
      }).catch((error) => {
        console.warn('Finance Compass offline cache unavailable:', error);
      });
  }
  if (document.readyState === 'complete') registerWorker();
  else window.addEventListener('load', registerWorker, { once: true });
}

(() => {
  const databaseName = 'finance-compass-sync';
  const storeName = 'ledger-outbox';

  function openDatabase() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) {
        reject(new Error('IndexedDB is unavailable'));
        return;
      }
      const request = window.indexedDB.open(databaseName, 1);
      let blocked = false;
      request.onupgradeneeded = () => request.result.createObjectStore(storeName);
      request.onerror = () => reject(request.error);
      request.onblocked = () => {
        blocked = true;
        reject(new Error('Opening the ledger outbox was blocked'));
      };
      request.onsuccess = () => {
        if (blocked) request.result.close();
        else resolve(request.result);
      };
    });
  }

  function openTransaction(database, mode) {
    if (mode === 'readonly') return database.transaction(storeName, mode);
    try {
      return database.transaction(storeName, mode, { durability: 'strict' });
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
      return database.transaction(storeName, mode);
    }
  }

  async function transactionFor(accountId, mode, action) {
    const database = await openDatabase();
    try {
      return await new Promise((resolve, reject) => {
        const transaction = openTransaction(database, mode);
        const store = transaction.objectStore(storeName);
        let result;
        transaction.oncomplete = () => resolve(result);
        transaction.onabort = () => reject(transaction.error ?? new Error('Ledger outbox transaction aborted'));
        const request = store.get(accountId);
        request.onsuccess = () => {
          try {
            const stored = request.result;
            if (stored !== undefined &&
                (typeof stored?.username !== 'string' || typeof stored?.identity !== 'string' ||
                 typeof stored?.payload !== 'string')) {
              throw new Error('Invalid stored ledger outbox');
            }
            result = action(stored, store);
          } catch (error) {
            reject(error);
            transaction.abort();
          }
        };
      });
    } finally {
      database.close();
    }
  }

  window.FinanceCompassLedgerOutbox = Object.freeze({
    read(accountId, username) {
      return transactionFor(accountId, 'readonly', stored => {
        if (stored && stored.username !== username) return { conflict: true };
        return { conflict: false, identity: stored?.identity, payload: stored?.payload };
      });
    },

    replace(accountId, username, expectedIdentity, nextIdentity, payload) {
      // Compare and replace within one IndexedDB transaction. Another tab
      // cannot commit a different queue between our read and our update.
      return transactionFor(accountId, 'readwrite', (stored, store) => {
        if ((stored && stored.username !== username) ||
            (stored?.identity ?? null) !== (expectedIdentity ?? null)) return false;
        if (nextIdentity == null) {
          if (stored) store.delete(accountId);
        } else {
          if (typeof nextIdentity !== 'string' || typeof payload !== 'string') {
            throw new Error('Invalid replacement ledger outbox');
          }
          store.put({ username, identity: nextIdentity, payload }, accountId);
        }
        return true;
      });
    },
  });
})();

(() => {
  const storageKey = 'finance-compass-push-device';
  let readyRegistration;
  let timezoneTail = Promise.resolve();
  const supported = () => window.isSecureContext && 'Notification' in window &&
    'PushManager' in window && 'serviceWorker' in navigator;

  function device() {
    try {
      const record = JSON.parse(localStorage.getItem(storageKey));
      return record && typeof record.accountId === 'string' &&
        typeof record.endpoint === 'string' ? record : null;
    } catch (_) {
      return null;
    }
  }

  async function closeReminders(registration, shouldClose) {
    if (typeof registration?.getNotifications !== 'function') return;
    try {
      for (const item of await registration.getNotifications()) {
        if (shouldClose(item.data?.accountId)) item.close();
      }
    } catch (_) {
      // Notification-centre access and PushManager permissions are independent.
    }
  }

  async function remove(registration, subscription) {
    if (subscription && !await subscription.unsubscribe() &&
        (await registration.pushManager.getSubscription())?.endpoint === subscription.endpoint) {
      throw new Error('Unable to unsubscribe from browser push');
    }
  }

  const timezone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const matches = (record, accountId, endpoint) =>
    record?.accountId === accountId && record.endpoint === endpoint;

  async function changeRegistration(method, accountId, payload) {
    const response = await fetch('/api/sync/v1/push/subscription', {
      method, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { 'Content-Type': 'application/json', 'X-Finance-Account': accountId },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(8000),
    });
    if (response.status !== 204) throw new Error('Push registration was not updated');
  }

  function refreshTimezone(accountId) {
    const update = timezoneTail.then(async () => {
      const record = device();
      const currentZone = timezone();
      if (!record?.confirmed || record.accountId !== accountId || record.timezone === currentZone) return;
      const registration = await navigator.serviceWorker.getRegistration();
      const subscription = await registration?.pushManager?.getSubscription();
      if (subscription?.endpoint !== record.endpoint) return;
      await changeRegistration('PATCH', accountId, { endpoint: record.endpoint, timezone: currentZone });
      const current = device();
      if (current?.confirmed && matches(current, accountId, record.endpoint)) {
        localStorage.setItem(storageKey, JSON.stringify({ ...current, timezone: currentZone }));
      }
    });
    timezoneTail = update.catch(() => {});
    return update;
  }

  async function unsubscribe(accountId) {
    const record = device();
    const closeOwned = async (registration) => {
      registration?.active?.postMessage({ type: 'finance-compass-push-transition' });
      await closeReminders(registration, owner => !owner || owner === accountId);
    };
    if (!record || record.accountId !== accountId) {
      if ('serviceWorker' in navigator) await closeOwned(await navigator.serviceWorker.getRegistration());
      return '';
    }
    let marked = false;
    try {
      localStorage.setItem(storageKey, JSON.stringify({ ...record, confirmed: false, revoking: true }));
      marked = true;
    } catch (_) {
      // Still revoke on the server and at the provider if storage is full.
    }
    const stopRemote = changeRegistration('DELETE', accountId, { endpoint: record.endpoint });
    const stopLocal = (async () => {
      const registration = await navigator.serviceWorker.getRegistration();
      await closeOwned(registration);
      const sub = await registration?.pushManager?.getSubscription();
      if (!matches(device(), accountId, record.endpoint) || (marked && !device()?.revoking)) return;
      if (sub?.endpoint === record.endpoint) await remove(registration, sub);
      if (matches(device(), accountId, record.endpoint) && device()?.revoking) localStorage.removeItem(storageKey);
    })();
    const [remote, local] = await Promise.allSettled([stopRemote, stopLocal]);
    if (remote.status === 'rejected' && local.status === 'rejected') throw local.reason;
    return record.endpoint;
  }

  window.FinanceCompassPush = Object.freeze({
    async inspect(accountId) {
      if (!supported()) return JSON.stringify({ supported: false, permission: 'denied' });
      if (Notification.permission === 'denied') {
        return JSON.stringify({ supported: true, permission: 'denied' });
      }
      readyRegistration = await navigator.serviceWorker.ready;
      if (device()?.accountId !== accountId) await reconcile(accountId).catch(() => {});
      const subscription = await readyRegistration.pushManager.getSubscription();
      const record = device();
      const endpoint = record?.accountId === accountId ? record.endpoint : null;
      if (record?.confirmed && endpoint && subscription?.endpoint === endpoint) {
        void refreshTimezone(accountId).catch(() => {});
      }
      return JSON.stringify({
        supported: true,
        permission: Notification.permission,
        enabled: Boolean(endpoint && record.confirmed && subscription?.endpoint === endpoint),
        endpoint,
      });
    },

    subscribe(accountId, publicKey) {
      if (!readyRegistration) return Promise.reject(new Error('Service worker is not ready'));
      const record = device();
      if (record && record.accountId !== accountId) {
        return Promise.reject(new Error('Push is enabled for a different account'));
      }
      const key = publicKey.replace(/-/g, '+').replace(/_/g, '/');
      const bytes = Uint8Array.from(atob(key.padEnd(Math.ceil(key.length / 4) * 4, '=')),
        (character) => character.charCodeAt(0));
      // Call subscribe synchronously in the click event. Waiting for the
      // service worker or making a network request here drops Safari's gesture.
      return readyRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: bytes,
      }).then(async (subscription) => {
        const endpoint = subscription.endpoint;
        try {
          localStorage.setItem(storageKey, JSON.stringify({
            accountId, endpoint, confirmed: false,
          }));
        } catch (error) {
          await remove(readyRegistration, subscription);
          throw error;
        }
        return JSON.stringify({
          subscription: subscription.toJSON(),
          timezone: timezone(),
        });
      });
    },

    confirm(accountId, endpoint, acknowledgedZone) {
      const record = device();
      if (!matches(record, accountId, endpoint) || record.revoking) {
        throw new Error('Browser push ownership changed');
      }
      localStorage.setItem(storageKey, JSON.stringify({ accountId, endpoint, timezone: acknowledgedZone, confirmed: true }));
    },

    unsubscribe,
    refreshTimezone,

    reconcile,
  });

  async function reconcile(accountId, verifiedTransition = false) {
    if (!('serviceWorker' in navigator)) return;
    const registration = await navigator.serviceWorker.getRegistration();
    if (verifiedTransition) {
      registration?.active?.postMessage({ type: 'finance-compass-push-transition' });
      await closeReminders(registration, owner => owner !== accountId);
    }
    const record = device();
    const subscription = await registration?.pushManager?.getSubscription();
    if (device()?.accountId !== record?.accountId || device()?.endpoint !== record?.endpoint) return;
    if (record?.accountId === accountId && subscription?.endpoint === record.endpoint) {
      if (record.revoking) await unsubscribe(accountId);
      else await refreshTimezone(accountId);
      return;
    }
    // A tab can resume after a different tab changed the cookie. Never
    // detach that other account's working subscription on a stale tab's word.
    if (record || subscription) {
      const response = await fetch('/api/sync/v1/ledger/revision', {
        credentials: 'same-origin', cache: 'no-store', redirect: 'error',
        headers: { 'X-Finance-Account': accountId }, signal: AbortSignal.timeout(8000),
      });
      if (!response.ok || (await response.json()).accountId !== accountId) return;
      if (device()?.accountId !== record?.accountId || device()?.endpoint !== record?.endpoint) return;
    }
    if (!verifiedTransition && (record || subscription)) {
      registration?.active?.postMessage({ type: 'finance-compass-push-transition' });
      await closeReminders(registration, owner => owner !== accountId);
    }
    if (subscription || record) {
      await remove(registration, subscription);
      if (device()?.accountId === record?.accountId && device()?.endpoint === record?.endpoint) {
        localStorage.removeItem(storageKey);
      }
    }
  }
})();
