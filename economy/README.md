# Robot economy on NEAR

## Setup and verification

The market uses credits as its currency. The following instructions use NEAR testnet.

The deployed contract is `robot-contract-7133014f3f.testnet`. Public transaction hashes and test accounts are in `testnet-results.json`; it contains no private keys. Use Node.js >= 22.22.2. The contract requires Rust with the `wasm32-unknown-unknown` target.

### Read-only verification of the existing deployment

From this directory:

```sh
npm ci
npm test
npm run verify:testnet
```

Expected: two relay-policy tests pass. The testnet verification command checks successful transactions for deployment, relayed sale, NPC manufacturing, module purchase and loss. It needs network access but no wallet or private key. Historical balances in `testnet-results.json` describe the end of the original demo; later transactions may change current balances. NEAR testnet state and public RPCs can be reset or become unavailable.

### Reproduce with fresh testnet accounts

These steps create four funded testnet accounts through the public testnet helper, compile and deploy the contract, then execute a full scenario. The helper may rate-limit or be unavailable. This does not register a mainnet prize wallet.

```sh
npm ci
rustup target add wasm32-unknown-unknown
cargo build --locked --release --target wasm32-unknown-unknown --manifest-path contract/Cargo.toml
node services/create-testnet-accounts.js
node services/demo.js --deploy
node services/verify-testnet.js --local
npm run verify:service
npm run verify:auto-sale
npm run verify:nep245
node services/npc.js --once
```

Expected demo: player receives five iron with no bids, NPC opens a 12-credit bid, player sells via signed NEP-366 delegate and sponsored relayer, NPC manufactures and sells a Plasma Gun, then a trusted loss destroys it. Final player balance is 95 credits, zero iron and zero Plasma Gun. `verify:service` checks authentication and duplicate-run rejection. `verify:auto-sale` places a temporary NPC bid and verifies a successful run sells ore automatically. `verify:nep245` transfers one credit between player and NPC, then returns it with a batch transfer. NPC creates funded buy orders and crafts or sells available modules.

`demo.js --deploy` is **one-shot for fresh accounts**; it deploys to the contract account and initializes state. Never rerun it against an existing initialized deployment. If a run stops midway, inspect the chain before retrying; generate a separate fresh set of accounts instead of blindly redeploying. The demo writes `.private/demo-results.json`; `--local` verifies that report, while the default command verifies the public historical report.

`create-testnet-accounts.js` writes keys to `.private/accounts.json` with mode 0600; `.private/` is ignored by Git. Keep this file locally for later testnet transactions. Never print keys, commit them, use them on mainnet, or paste them into a public report. The example accounts are test-only and use a third-party faucet.

### Run services

The commands below use the accounts in `.private/accounts.json` and a deployed, initialized contract on those accounts. `NEAR_RPC_URL` can override the testnet RPC.

```sh
npm run npc
npm run relayer
GAME_SERVICE_TOKEN='<at least 32 secret bytes>' npm run game-service
```

The NPC runs a cycle every 30 seconds; `--once` runs one cycle. The relayer listens only on localhost:3030 and accepts `POST /relay` with a base64-encoded NEP-366 signed delegate. It sponsors one zero-deposit call to an allowlisted market method, targeting this contract and the configured test player. It never receives the player's private key. A browser wallet needs delegate-action signing to use the relayer. The game service listens on localhost:3031 and accepts authenticated `POST /settle` requests; it uses the contract authority key and trusts the submitted results and equipped-module data. Its bearer token and authority access belong only to a trusted game server. The NPC service holds the NPC account key.

## Economy and implementation

- `contract/src/lib.rs` uses `near-sdk-contract-tools`' NEP-245 implementation. `iron`, `copper`, `cobalt`, `credit` and nine existing non-default module IDs are tokens. The NEP-245 approval and metadata extensions are not implemented.
- The authority grants initial inventory and credits and settles unique run IDs. A win creates the reported ore and sells it against the highest bids, oldest first at equal price; unsold ore stays with the player. A loss burns the modules reported by the trusted authority. The contract currently has no player governance.
- Anyone with tokens can reserve credits for a buy order or reserve ore/modules for a sell order. The contract holds those tokens in escrow, matches a fill at the order price and returns remaining escrow on cancellation. Orders are capped at 200. Players can also manufacture modules from the same recipes as NPCs.
- The NPC uses its own account, buys ore with its finite credit balance, crafts modules from its inventory, and sells them. Bid prices for new orders fall with the NPC's current free ore stock; sell prices use configured base ingredient costs plus a margin. It does not claim to predict market prices or use an LLM. All nine recipes are in `recipe()` in the contract.
- Credits are issued by the authority during setup and then transferred between participants. There is no automatic unlimited currency creation. Empty demand means unsold ore remains in inventory; depleted NPC funds mean it cannot make further bids until it earns credits.
- The relayer, NPC and trusted game service are independent off-chain programs. The signed NEP-366 delegate is authorized by the player and submitted by the relayer.
- The contract account pays for on-chain storage. Opening the services to additional users requires storage accounting, resource limits, security review and abuse controls.
