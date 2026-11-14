import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { accounts } from './common.js';

const token = randomBytes(32).toString('hex');
const port = 3032;
const child = spawn(process.execPath, ['services/game-service.js'], {
  cwd: process.cwd(), env: { ...process.env, GAME_SERVICE_TOKEN: token, GAME_SERVICE_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'inherit'],
});
try {
  await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', code => reject(new Error(`game service exited ${code}`)));
    child.stdout.once('data', resolve);
  });
  const payload = { run_id: `service-test-${randomBytes(8).toString('hex')}`, player: accounts.player.accountId, won: true, ore: ['0', '0', '0'], lost_modules: [] };
  const send = authorization => fetch(`http://127.0.0.1:${port}/settle`, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization }, body: JSON.stringify(payload),
  });
  assert.equal((await send('Bearer invalid')).status, 401);
  const success = await send(`Bearer ${token}`);
  assert.equal(success.status, 200, JSON.stringify(await success.json()));
  const replay = await send(`Bearer ${token}`);
  assert.equal(replay.status, 400, 'duplicate run must be rejected');
  console.log('Game service: authentication, settlement and duplicate rejection OK');
} finally {
  child.kill();
}
