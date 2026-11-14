use std::collections::HashSet;

use near_sdk::{env, json_types::U128, near, require, AccountId, PanicOnDefault};
use near_sdk_contract_tools::standard::nep245::{
    Nep245Burn, Nep245Controller, Nep245Mint, Nep245Transfer,
};
use near_sdk_contract_tools::Nep245;

const CREDIT: &str = "credit";
const ORES: [&str; 3] = ["iron", "copper", "cobalt"];
const MODULES: [&str; 9] = [
    "Body_A_Box",
    "Body_B_Wedge",
    "Body_D_Sphere",
    "Head_A_Visor",
    "Legs_A_Standard",
    "Legs_B_Insect",
    "Right_A_Gripper",
    "Right_B_Welder",
    "Right_C_LightRocket",
];
const MAX_ORDERS: usize = 200;

#[near(serializers = [borsh, json])]
#[derive(Clone)]
pub struct Order {
    pub id: u64,
    pub owner: AccountId,
    pub token_id: String,
    pub buy: bool,
    pub price: U128,
    pub remaining: U128,
}

#[near(contract_state)]
#[derive(PanicOnDefault, Nep245)]
pub struct Economy {
    authority: AccountId,
    orders: Vec<Order>,
    next_order: u64,
    completed_runs: HashSet<String>,
}

#[near]
impl Economy {
    #[init]
    pub fn new(authority: AccountId) -> Self {
        let mut contract = Self {
            authority,
            orders: Vec::new(),
            next_order: 0,
            completed_runs: HashSet::new(),
        };
        for id in [CREDIT].iter().chain(ORES.iter()).chain(MODULES.iter()) {
            contract
                .create_token((*id).to_string())
                .expect("token id must be unique");
        }
        contract
    }

    /// Testnet bootstrap only. The authority funds participants and the NPC.
    pub fn grant(&mut self, account_id: AccountId, token_id: String, amount: U128) {
        self.assert_authority();
        require!(
            amount.0 > 0 && self.token_exists(&token_id),
            "invalid grant"
        );
        self.issue(&account_id, &token_id, amount.0);
    }

    /// Trusted game service reports each run once. A failed run burns specified modules.
    pub fn settle_run(
        &mut self,
        run_id: String,
        player: AccountId,
        won: bool,
        ore: Vec<U128>,
        lost_modules: Vec<String>,
    ) {
        self.assert_authority();
        require!(
            !run_id.is_empty() && run_id.len() <= 128 && !self.completed_runs.contains(&run_id),
            "invalid or duplicate run"
        );
        require!(ore.len() == ORES.len(), "expected three ore amounts");
        require!(
            if won {
                lost_modules.is_empty()
            } else {
                ore.iter().all(|x| x.0 == 0)
            },
            "inconsistent run result"
        );
        let mut unique = HashSet::new();
        for id in &lost_modules {
            require!(
                MODULES.contains(&id.as_str()) && unique.insert(id.clone()),
                "invalid or duplicate module"
            );
            require!(
                self.balance_of(id, &player) >= 1,
                "player does not own module"
            );
        }
        self.completed_runs.insert(run_id);
        if won {
            for (id, amount) in ORES.iter().zip(ore) {
                if amount.0 > 0 {
                    self.issue(&player, id, amount.0);
                    self.sell_ore_for(&player, id, amount.0);
                }
            }
        } else {
            for id in lost_modules {
                self.destroy(&player, &id, 1);
            }
        }
    }

    /// Reserve credits for a bid, or items for an ask, in contract escrow.
    pub fn place_order(&mut self, token_id: String, buy: bool, price: U128, amount: U128) -> u64 {
        require!(
            ORES.contains(&token_id.as_str()) || MODULES.contains(&token_id.as_str()),
            "unknown market token"
        );
        require!(
            price.0 > 0 && amount.0 > 0 && self.orders.len() < MAX_ORDERS,
            "invalid order or order limit"
        );
        let owner = env::predecessor_account_id();
        let escrow = env::current_account_id();
        let (asset, reserved) = if buy {
            (
                CREDIT,
                price.0.checked_mul(amount.0).expect("order value overflow"),
            )
        } else {
            (token_id.as_str(), amount.0)
        };
        self.move_tokens(&owner, &escrow, asset, reserved);
        let id = self.next_order;
        self.next_order = self.next_order.checked_add(1).expect("order id overflow");
        self.orders.push(Order {
            id,
            owner,
            token_id,
            buy,
            price,
            remaining: amount,
        });
        id
    }

    pub fn cancel_order(&mut self, id: u64) {
        let index = self
            .orders
            .iter()
            .position(|o| o.id == id)
            .expect("order not found");
        let order = self.orders[index].clone();
        require!(
            order.owner == env::predecessor_account_id(),
            "not order owner"
        );
        let (asset, amount) = if order.buy {
            (
                CREDIT,
                order
                    .price
                    .0
                    .checked_mul(order.remaining.0)
                    .expect("overflow"),
            )
        } else {
            (order.token_id.as_str(), order.remaining.0)
        };
        self.move_tokens(&env::current_account_id(), &order.owner, asset, amount);
        self.orders.remove(index);
    }

    /// Fill the other party's reserved order at its advertised price.
    pub fn fill_order(&mut self, id: u64, amount: U128) {
        self.fill_order_for(&env::predecessor_account_id(), id, amount.0);
    }

    /// Sell available ore to the best bids; unsold ore remains with the player.
    pub fn sell_ore(&mut self, token_id: String, amount: U128) -> U128 {
        require!(
            ORES.contains(&token_id.as_str()) && amount.0 > 0,
            "invalid ore sale"
        );
        let seller = env::predecessor_account_id();
        require!(
            self.balance_of(&token_id, &seller) >= amount.0,
            "insufficient ore"
        );
        U128(self.sell_ore_for(&seller, &token_id, amount.0))
    }

    fn fill_order_for(&mut self, taker: &AccountId, id: u64, amount: u128) {
        require!(amount > 0, "zero amount");
        let index = self
            .orders
            .iter()
            .position(|o| o.id == id)
            .expect("order not found");
        let order = self.orders[index].clone();
        require!(
            order.owner != *taker && amount <= order.remaining.0,
            "invalid fill"
        );
        let value = amount.checked_mul(order.price.0).expect("value overflow");
        let escrow = env::current_account_id();
        if order.buy {
            self.move_tokens(taker, &order.owner, &order.token_id, amount);
            self.move_tokens(&escrow, taker, CREDIT, value);
        } else {
            self.move_tokens(taker, &order.owner, CREDIT, value);
            self.move_tokens(&escrow, taker, &order.token_id, amount);
        }
        self.orders[index].remaining.0 -= amount;
        if self.orders[index].remaining.0 == 0 {
            self.orders.remove(index);
        }
    }

    fn sell_ore_for(&mut self, seller: &AccountId, token_id: &str, amount: u128) -> u128 {
        let mut remaining = amount;
        while remaining > 0 {
            let best = self
                .orders
                .iter()
                .filter(|o| o.buy && o.token_id == token_id && o.owner != *seller)
                .max_by(|a, b| a.price.0.cmp(&b.price.0).then_with(|| b.id.cmp(&a.id)))
                .map(|o| (o.id, o.remaining.0));
            let Some((id, available)) = best else { break };
            let fill = remaining.min(available);
            self.fill_order_for(seller, id, fill);
            remaining -= fill;
        }
        amount - remaining
    }

    /// Manufacture one module from the caller's own ore.
    pub fn manufacture(&mut self, module_id: String) {
        let recipe = recipe(&module_id).expect("unknown module");
        let maker = env::predecessor_account_id();
        for (ore, amount) in ORES.iter().zip(recipe) {
            require!(self.balance_of(ore, &maker) >= amount, "insufficient ore");
        }
        for (ore, amount) in ORES.iter().zip(recipe) {
            if amount > 0 {
                self.destroy(&maker, ore, amount);
            }
        }
        self.issue(&maker, &module_id, 1);
    }

    pub fn get_orders(&self) -> Vec<Order> {
        self.orders.clone()
    }
    pub fn get_recipe(&self, module_id: String) -> Option<Vec<U128>> {
        recipe(&module_id).map(|r| r.into_iter().map(U128).collect())
    }

    fn assert_authority(&self) {
        require!(
            env::predecessor_account_id() == self.authority,
            "authority only"
        );
    }
    fn issue(&mut self, owner: &AccountId, id: &str, amount: u128) {
        self.mint(&Nep245Mint::single(id, amount, owner.clone()))
            .unwrap_or_else(|e| env::panic_str(&e.to_string()));
    }
    fn destroy(&mut self, owner: &AccountId, id: &str, amount: u128) {
        self.burn(&Nep245Burn::single(id, amount, owner.clone()))
            .unwrap_or_else(|e| env::panic_str(&e.to_string()));
    }
    fn move_tokens(&mut self, from: &AccountId, to: &AccountId, id: &str, amount: u128) {
        self.transfer(&Nep245Transfer::single(
            from.clone(),
            to.clone(),
            id,
            amount,
            None::<&str>,
        ))
        .unwrap_or_else(|e| env::panic_str(&e.to_string()));
    }
}

fn recipe(id: &str) -> Option<[u128; 3]> {
    Some(match id {
        "Body_A_Box" => [15, 5, 2],
        "Body_B_Wedge" => [12, 5, 1],
        "Body_D_Sphere" => [12, 4, 2],
        "Head_A_Visor" => [10, 5, 1],
        "Legs_A_Standard" => [15, 4, 1],
        "Legs_B_Insect" => [14, 5, 2],
        "Right_A_Gripper" => [15, 6, 2],
        "Right_B_Welder" => [4, 2, 0],
        "Right_C_LightRocket" => [14, 5, 2],
        _ => return None,
    })
}
