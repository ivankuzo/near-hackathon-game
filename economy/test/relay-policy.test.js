import { test } from 'node:test';
import assert from 'node:assert/strict';
import { actions } from 'near-api-js';
import { validateSponsored } from '../services/relay-policy.js';

const base = () => ({ senderId: 'player.testnet', receiverId: 'game.testnet', actions: [actions.functionCall('sell_ore', {}, 30_000_000_000_000n, 0n)] });
const check = value => validateSponsored(value, 'player.testnet', 'game.testnet');

test('allows a single approved contract call without attached funds', () => assert.doesNotThrow(() => check(base())));
test('rejects unexpected sender, receiver, methods, deposit and excessive gas', () => {
  for (const change of [
    { senderId: 'attacker.testnet' }, { receiverId: 'attacker.testnet' },
    { actions: [actions.functionCall('grant', {}, 1n, 0n)] },
    { actions: [actions.functionCall('sell_ore', {}, 1n, 1n)] },
    { actions: [actions.functionCall('sell_ore', {}, 100_000_000_000_001n, 0n)] },
    { actions: [actions.functionCall('sell_ore', {}, 1n, 0n), actions.functionCall('grant', {}, 1n, 0n)] },
  ]) assert.throws(() => check({ ...base(), ...change }));
});
