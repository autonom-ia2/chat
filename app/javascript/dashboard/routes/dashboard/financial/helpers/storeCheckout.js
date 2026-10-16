export const isStorePilot = target =>
  (target?.type === 'feature' && target.featureKey === 'prospecting') ||
  (target?.type === 'agent' &&
    Number.isInteger(target.principalAgentId) &&
    target.principalAgentId > 0);

export const canActivateStoreEntry = entry => {
  const allocation = entry.subscription.limits.filter(
    limit =>
      limit.usageBehavior === 'allocation' && limit.resetPeriod === 'none'
  );
  return (
    isStorePilot(entry.target) &&
    entry.subscription.access.allowed &&
    allocation.length === 1
  );
};

export const checkoutStorageKey = (userId, accountId) =>
  `autonomia-store-checkout:${userId}:${accountId}`;

export const readCheckoutIntent = key => {
  const value = sessionStorage.getItem(key);
  if (!value) return null;
  const record = JSON.parse(value);
  if (
    !record ||
    typeof record.clientIntent !== 'string' ||
    typeof record.priceId !== 'string'
  )
    throw new Error('Invalid local checkout intent.');
  return record;
};

export const writeCheckoutIntent = (key, value) =>
  sessionStorage.setItem(key, JSON.stringify(value));

export const clearCheckoutIntent = (key, operationId, clientIntent) => {
  const record = readCheckoutIntent(key);
  if (
    record?.operationId === operationId ||
    (clientIntent && record?.clientIntent === clientIntent)
  )
    sessionStorage.removeItem(key);
};
