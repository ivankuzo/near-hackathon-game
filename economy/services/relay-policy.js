const allowed = new Set(['place_order', 'cancel_order', 'fill_order', 'sell_ore', 'manufacture']);

export function validateSponsored(delegate, playerId, contractId) {
  if (delegate.senderId !== playerId || delegate.receiverId !== contractId || delegate.actions.length !== 1) throw new Error('Sender or target not allowed');
  const action = delegate.actions[0].functionCall;
  if (!action || !allowed.has(action.methodName) || action.deposit !== 0n || action.gas > 100_000_000_000_000n) throw new Error('Action not sponsored');
}
