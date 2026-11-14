import { accounts, call, view } from './common.js';

const prices = { iron: 12, copper: 25, cobalt: 45 };
const modules = ['Body_A_Box', 'Body_B_Wedge', 'Body_D_Sphere', 'Head_A_Visor',
  'Legs_A_Standard', 'Legs_B_Insect', 'Right_A_Gripper', 'Right_B_Welder', 'Right_C_LightRocket'];
const ores = Object.keys(prices);
const npcId = accounts.npc.accountId;
const balance = async token_id => BigInt(await view('mt_balance_of', { account_id: npcId, token_id }));

async function tick() {
  const open = (await view('get_orders')).filter(order => order.owner === npcId);
  for (const ore of ores) {
    const stock = await balance(ore);
    const price = BigInt(Math.max(1, prices[ore] - Number(stock / 20n)));
    const existing = open.find(order => order.buy && order.token_id === ore);
    if (existing && BigInt(existing.price) === price) continue;
    if (existing) await call('npc', 'cancel_order', { id: existing.id });
    const credits = await balance('credit');
    const amount = credits / price < 10n ? credits / price : 10n;
    if (amount > 0n) await call('npc', 'place_order', { token_id: ore, buy: true, price: String(price), amount: String(amount) });
  }
  for (const module of modules) {
    if (open.some(order => !order.buy && order.token_id === module)) continue;
    if (await balance(module) === 0n) {
      const recipe = (await view('get_recipe', { module_id: module })).map(BigInt);
      const stocks = await Promise.all(ores.map(balance));
      if (recipe.some((quantity, i) => stocks[i] < quantity)) continue;
      await call('npc', 'manufacture', { module_id: module });
    }
    const recipe = (await view('get_recipe', { module_id: module })).map(BigInt);
    const cost = recipe.reduce((sum, quantity, i) => sum + quantity * BigInt(prices[ores[i]]), 0n);
    await call('npc', 'place_order', { token_id: module, buy: false, price: String(cost * 12n / 10n), amount: '1' });
  }
  console.log('NPC cycle complete');
}

if (process.argv.includes('--once')) {
  await tick();
} else {
  while (true) {
    await tick();
    await new Promise(resolve => setTimeout(resolve, 30_000));
  }
}
