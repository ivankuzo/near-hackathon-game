import { randomBytes } from 'node:crypto';
import { chmod, mkdir, readFile, writeFile } from 'node:fs/promises';
import { KeyPair } from 'near-api-js';

const path = new URL('../.private/accounts.json', import.meta.url);
await mkdir(new URL('../.private/', import.meta.url), { recursive: true, mode: 0o700 });
let accounts;
try {
  accounts = JSON.parse(await readFile(path, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  const suffix = randomBytes(5).toString('hex');
  accounts = Object.fromEntries(['contract', 'npc', 'player', 'relayer'].map(role => {
    const key = KeyPair.fromRandom('ed25519');
    return [role, { accountId: `robot-${role}-${suffix}.testnet`, publicKey: key.getPublicKey().toString(), privateKey: key.toString() }];
  }));
  await writeFile(path, JSON.stringify(accounts, null, 2), { mode: 0o600, flag: 'wx' });
  await chmod(path, 0o600);
}

for (const [role, account] of Object.entries(accounts)) {
  if (account.created) continue;
  const response = await fetch('https://helper.testnet.near.org/account', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ newAccountId: account.accountId, newAccountPublicKey: account.publicKey }),
  });
  if (!response.ok) throw new Error(`testnet faucet failed for ${role}: ${response.status} ${await response.text()}`);
  account.created = true;
  await writeFile(path, JSON.stringify(accounts, null, 2), { mode: 0o600 });
  console.log(`${role}: ${account.accountId}`);
}
