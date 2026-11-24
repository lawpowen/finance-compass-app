import { openStore, usernameValid } from './store.mjs';

async function readPassword() {
  const input = [];
  let bytes = 0;
  for await (const chunk of process.stdin) {
    bytes += chunk.length;
    if (bytes > 258) throw new Error('Password input exceeds 256 UTF-8 bytes.');
    input.push(chunk);
  }
  return new TextDecoder('utf-8', { fatal: true })
    .decode(Buffer.concat(input, bytes))
    .replace(/\r?\n$/, '');
}

process.umask(0o077);
const username = process.argv[2];
if (process.argv.length !== 3 || !usernameValid(username) || process.stdin.isTTY) {
  console.error('Pipe the password to stdin and run node server/provision.mjs <username>.');
  process.exitCode = 1;
} else {
  let store;
  try {
    const password = await readPassword();
    store = openStore();
    await store.provision(username, password);
    console.info('Finance sync account saved. Existing sessions for this account have been revoked.');
  } catch (error) {
    console.error('Account setup failed:', error.message);
    process.exitCode = 1;
  } finally {
    store?.close();
  }
}
