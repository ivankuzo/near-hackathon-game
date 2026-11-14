import assert from 'node:assert/strict';
import { account, accounts, contractId, view } from './common.js';

const balance = async role => BigInt(await view('mt_balance_of', { account_id: accounts[role].accountId, token_id: 'credit' }));
const playerBefore = await balance('player');
const npcBefore = await balance('npc');
assert.ok(playerBefore >= 1n, 'Player needs at least one credit');
const playerTransfer = await account('player').callFunctionRaw({
  contractId, methodName: 'mt_transfer', deposit: 1n, gas: 50_000_000_000_000n, waitUntil: 'FINAL',
  args: { receiver_id: accounts.npc.accountId, token_id: 'credit', amount: '1', approval: null, memo: null },
});
assert.equal(await balance('npc'), npcBefore + 1n);
const npcReturn = await account('npc').callFunctionRaw({
  contractId, methodName: 'mt_batch_transfer', deposit: 1n, gas: 50_000_000_000_000n, waitUntil: 'FINAL',
  args: { receiver_id: accounts.player.accountId, token_ids: ['credit'], amounts: ['1'], approvals: null, memo: null },
});
assert.equal(await balance('player'), playerBefore);
assert.equal(await balance('npc'), npcBefore);
console.log(`NEP-245 transfer and batch transfer OK: ${playerTransfer.transaction.hash} ${npcReturn.transaction.hash}`);
