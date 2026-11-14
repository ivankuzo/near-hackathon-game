import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { account, accounts, contractId, view } from './common.js';

const balance = async (role, token_id) => BigInt(await view('mt_balance_of', { account_id: accounts[role].accountId, token_id }));
const send = async (role, methodName, args) => account(role).callFunctionRaw({ contractId, methodName, args, gas: 100_000_000_000_000n, deposit: 0n, waitUntil: 'FINAL' });
const beforePlayer = await balance('player', 'credit');
const beforeNpc = await balance('npc', 'iron');
const bid = await send('npc', 'place_order', { token_id: 'iron', buy: true, price: '999', amount: '2' });
const settled = await send('contract', 'settle_run', {
  run_id: `auto-${randomBytes(8).toString('hex')}`, player: accounts.player.accountId,
  won: true, ore: ['2', '0', '0'], lost_modules: [],
});
assert.equal(await balance('player', 'credit'), beforePlayer + 1998n);
assert.equal(await balance('npc', 'iron'), beforeNpc + 2n);
const report = { bid: bid.transaction.hash, settlement: settled.transaction.hash };
await writeFile(new URL('../.private/auto-sale-result.json', import.meta.url), JSON.stringify(report, null, 2));
console.log(`Automatic sale OK: ${JSON.stringify(report)}`);
