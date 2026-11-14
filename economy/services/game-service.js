import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { call } from './common.js';

const secret = process.env.GAME_SERVICE_TOKEN;
if (!secret || Buffer.byteLength(secret) < 32) throw new Error('GAME_SERVICE_TOKEN must be at least 32 bytes');

function authorized(value) {
  const expected = Buffer.from(`Bearer ${secret}`);
  const actual = Buffer.from(value || '');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

createServer(async (req, res) => {
  res.setHeader('content-type', 'application/json');
  try {
    if (req.method !== 'POST' || req.url !== '/settle') throw new Error('Expected POST /settle');
    if (!authorized(req.headers.authorization)) {
      res.statusCode = 401;
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }
    let body = '';
    for await (const chunk of req) {
      body += chunk;
      if (body.length > 8192) throw new Error('Request too large');
    }
    const result = JSON.parse(body);
    if (typeof result.run_id !== 'string' || typeof result.player !== 'string' || typeof result.won !== 'boolean' ||
        !Array.isArray(result.ore) || result.ore.length !== 3 ||
        !result.ore.every(x => typeof x === 'string' && /^(0|[1-9][0-9]{0,5})$/.test(x)) ||
        !Array.isArray(result.lost_modules) || result.lost_modules.length > 5 ||
        !result.lost_modules.every(x => typeof x === 'string')) throw new Error('Invalid run result');
    await call('contract', 'settle_run', result);
    res.end(JSON.stringify({ ok: true }));
  } catch (error) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: error.message }));
  }
}).listen(Number(process.env.GAME_SERVICE_PORT || 3031), '127.0.0.1', () => console.log('Trusted testnet game service started'));
