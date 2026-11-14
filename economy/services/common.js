import { readFile } from 'node:fs/promises';
import { Account, JsonRpcProvider } from 'near-api-js';

export const rpcUrl = process.env.NEAR_RPC_URL || 'https://test.rpc.fastnear.com';
export const provider = new JsonRpcProvider({ url: rpcUrl });
export const accounts = JSON.parse(await readFile(new URL('../.private/accounts.json', import.meta.url), 'utf8'));
export const contractId = accounts.contract.accountId;

export function account(role) {
  const entry = accounts[role];
  if (!entry?.accountId.endsWith('.testnet') || !entry.privateKey) throw new Error(`Missing testnet credentials for ${role}`);
  return new Account(entry.accountId, provider, entry.privateKey);
}

export async function view(methodName, args = {}) {
  const result = await provider.sendJsonRpc('query', {
    request_type: 'call_function', account_id: contractId, method_name: methodName,
    args_base64: Buffer.from(JSON.stringify(args)).toString('base64'), finality: 'final',
  });
  return JSON.parse(Buffer.from(result.result).toString());
}

export async function call(role, methodName, args) {
  return account(role).callFunction({ contractId, methodName, args, gas: 100_000_000_000_000n, deposit: 0n });
}
