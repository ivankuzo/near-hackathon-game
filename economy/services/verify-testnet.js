import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JsonRpcProvider } from 'near-api-js';

const reportPath = process.argv.includes('--local') ? '../.private/demo-results.json' : '../testnet-results.json';
const report = JSON.parse(await readFile(new URL(reportPath, import.meta.url), 'utf8'));
assert.equal(report.network, 'testnet');
const provider = new JsonRpcProvider({ url: process.env.NEAR_RPC_URL || 'https://test.rpc.fastnear.com' });
const checks = [
  ['deploy', 'contract'], ['relayed_sale', 'relayer'],
  ['npc_manufacture_10', 'npc'], ['player_fill_order_12', 'player'], ['contract_settle_run_13', 'contract'],
];
if (report.transactions.upgrade_auto_sale) checks.push(
  ['upgrade_auto_sale', 'contract'], ['auto_sale_bid', 'npc'], ['auto_sale_settlement', 'contract'],
);
if (report.transactions.nep245_transfer) checks.push(
  ['nep245_transfer', 'player'], ['nep245_batch_transfer', 'npc'],
);
if (report.transactions.final_build_deploy) checks.push(['final_build_deploy', 'contract']);
for (const [name, role] of checks) {
  const hash = report.transactions[name];
  assert.ok(hash, `Missing ${name}`);
  const tx = await provider.viewTransactionStatus({ txHash: hash, accountId: report.accounts[role], waitUntil: 'FINAL' });
  assert.ok(tx.status && 'SuccessValue' in tx.status, `${name} did not succeed: ${JSON.stringify(tx.status)}`);
  assert.equal(tx.transaction.receiver_id, name === 'relayed_sale' ? report.accounts.player : report.contractId);
  console.log(`${name}: ${hash} OK`);
}
console.log(`Testnet contract: ${report.contractId}`);
