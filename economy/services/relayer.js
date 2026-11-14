import { createServer } from 'node:http';
import { decodeSignedDelegate } from 'near-api-js';
import { account, accounts, contractId } from './common.js';
import { validateSponsored } from './relay-policy.js';

const relayer = account('relayer');
const port = Number(process.env.RELAYER_PORT || 3030);

createServer(async (req, res) => {
  res.setHeader('content-type', 'application/json');
  try {
    if (req.method !== 'POST' || req.url !== '/relay') throw new Error('Expected POST /relay');
    let body = '';
    for await (const chunk of req) {
      body += chunk;
      if (body.length > 16384) throw new Error('Request too large');
    }
    const { signedDelegate } = JSON.parse(body);
    if (typeof signedDelegate !== 'string') throw new Error('Missing signed delegate');
    const signed = decodeSignedDelegate(Buffer.from(signedDelegate, 'base64'));
    validateSponsored(signed.delegateAction, accounts.player.accountId, contractId);
    const result = await relayer.relayMetaTransaction(signed);
    res.end(JSON.stringify(result, (_, value) => typeof value === 'bigint' ? value.toString() : value));
  } catch (error) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: error.message }));
  }
}).listen(port, '127.0.0.1', () => console.log(`Testnet relayer listening on 127.0.0.1:${port}`));
