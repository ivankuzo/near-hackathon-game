import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { actions, encodeSignedDelegate } from 'near-api-js';
import { account, accounts, contractId, view } from './common.js';

if (!process.argv.includes('--deploy')) throw new Error('Demo deploys and initializes a new testnet contract; pass --deploy once.');
const resultFile = new URL('../.private/demo-results.json', import.meta.url);
try {
  await readFile(resultFile);
  throw new Error('Demo already completed; do not redeploy an initialized account.');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

const transactions = {};
const rawCall = async (role, methodName, args) => {
  const outcome = await account(role).callFunctionRaw({ contractId, methodName, args, gas: 100_000_000_000_000n, deposit: 0n, waitUntil: 'FINAL' });
  if (JSON.stringify(outcome.status).includes('Failure')) throw new Error(`${methodName} failed: ${JSON.stringify(outcome.status)}`);
  transactions[`${role}_${methodName}_${Object.keys(transactions).length}`] = outcome.transaction.hash;
  return outcome;
};
const wasm = await readFile(new URL('../contract/target/wasm32-unknown-unknown/release/robot_economy.wasm', import.meta.url));
const deploy = await account('contract').deployContract(wasm);
transactions.deploy = deploy.transaction.hash;
await rawCall('contract', 'new', { authority: contractId });
for (const [role, token, amount] of [
  ['npc', 'credit', '10000'], ['npc', 'iron', '30'], ['npc', 'copper', '20'],
  ['npc', 'cobalt', '10'], ['player', 'credit', '150'],
]) await rawCall('contract', 'grant', { account_id: accounts[role].accountId, token_id: token, amount });
await rawCall('contract', 'settle_run', { run_id: 'demo-win-1', player: accounts.player.accountId, won: true, ore: ['5', '0', '0'], lost_modules: [] });
await rawCall('npc', 'place_order', { token_id: 'iron', buy: true, price: '12', amount: '10' });

const child = spawn(process.execPath, ['services/relayer.js'], { cwd: process.cwd(), stdio: ['ignore', 'pipe', 'inherit'] });
try {
  await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', code => reject(new Error(`relayer exited ${code}`)));
    child.stdout.once('data', resolve);
  });
  const { signedDelegate } = await account('player').createSignedMetaTransaction({
    receiverId: contractId,
    actions: [actions.functionCall('sell_ore', { token_id: 'iron', amount: '5' }, 100_000_000_000_000n, 0n)],
    blockHeightTtl: 120,
  });
  const response = await fetch('http://127.0.0.1:3030/relay', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ signedDelegate: Buffer.from(encodeSignedDelegate(signedDelegate)).toString('base64') }),
  });
  const result = await response.json();
  if (!response.ok || JSON.stringify(result.status).includes('Failure')) throw new Error(`Relayed sale failed: ${JSON.stringify(result)}`);
  transactions.relayed_sale = result.transaction.hash;
} finally {
  child.kill();
}

await rawCall('npc', 'manufacture', { module_id: 'Right_B_Welder' });
await rawCall('npc', 'place_order', { token_id: 'Right_B_Welder', buy: false, price: '115', amount: '1' });
const orders = await view('get_orders');
const plasma = orders.find(o => !o.buy && o.token_id === 'Right_B_Welder');
if (!plasma) throw new Error('Missing Plasma Gun order');
await rawCall('player', 'fill_order', { id: plasma.id, amount: '1' });
await rawCall('contract', 'settle_run', { run_id: 'demo-loss-1', player: accounts.player.accountId, won: false, ore: ['0', '0', '0'], lost_modules: ['Right_B_Welder'] });
const balance = async (role, token_id) => view('mt_balance_of', { account_id: accounts[role].accountId, token_id });
const final = { player_iron: await balance('player', 'iron'), player_credit: await balance('player', 'credit'), player_plasma: await balance('player', 'Right_B_Welder'), npc_iron: await balance('npc', 'iron') };
if (final.player_iron !== '0' || final.player_credit !== '95' || final.player_plasma !== '0') throw new Error(`Unexpected final balances: ${JSON.stringify(final)}`);
const report = { network: 'testnet', contractId, accounts: Object.fromEntries(Object.entries(accounts).map(([role, value]) => [role, value.accountId])), transactions, final };
await writeFile(resultFile, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
