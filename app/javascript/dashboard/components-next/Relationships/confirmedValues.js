import { watch, effectScope } from 'vue';

// One ledger per application store, shared by the legacy actions and all editors.
const stores = new WeakMap();
const ledgerFor = store => {
  if (!stores.has(store)) {
    const ledger = { fields: new Map(), generation: 0 };
    const invalidate = () => {
      ledger.generation += 1;
      ledger.fields.clear();
    };
    store.subscribe(mutation => {
      if (mutation.type === 'CLEAR_USER') invalidate();
    });
    effectScope(true).run(() =>
      watch(
        () => [
          store.getters.getCurrentUserID,
          store.getters.getCurrentAccountId,
        ],
        invalidate,
        { flush: 'sync' }
      )
    );
    stores.set(store, ledger);
  }
  return stores.get(store);
};

export function beginFieldWrite(store, identity) {
  const ledger = ledgerFor(store);
  const generation = ledger.generation;
  const { fields } = ledger;
  if (!fields.has(identity)) fields.set(identity, { issued: 0, confirmed: 0 });
  const field = fields.get(identity);
  field.issued += 1;
  const sequence = field.issued;
  return () => {
    if (generation !== ledger.generation || sequence < field.confirmed)
      return false;
    field.confirmed = sequence;
    return true;
  };
}

export function recordRequest(store, accountId, entity, id) {
  const ledger = ledgerFor(store);
  const generation = ledger.generation;
  const user = store.getters.getCurrentUserID;
  const account = store.getters.getCurrentAccountId;
  const prefix = `${user}:${accountId}:${entity}:${id}:`;
  const before = new Map(
    [...ledger.fields].map(([key, value]) => [key, value.confirmed])
  );
  return {
    valid: () =>
      generation === ledger.generation &&
      user === store.getters.getCurrentUserID &&
      account === store.getters.getCurrentAccountId,
    // A GET issued before a confirmation cannot restore that field's old value.
    mergeRead(incoming = {}, live = {}) {
      const attributes = { ...incoming };
      ledger.fields.forEach((field, identity) => {
        if (
          identity.startsWith(prefix) &&
          field.confirmed > (before.get(identity) || 0)
        ) {
          const key = identity.slice(prefix.length);
          if (Object.hasOwn(live, key)) attributes[key] = live[key];
          else delete attributes[key];
        }
      });
      return attributes;
    },
    write(keys) {
      const confirmations = keys.map(key => [
        key,
        beginFieldWrite(store, `${prefix}${key}`),
      ]);
      return (live = {}, confirmed = {}) => {
        const attributes = { ...live };
        confirmations.forEach(([key, confirm]) => {
          if (!confirm()) return;
          if (Object.hasOwn(confirmed, key)) attributes[key] = confirmed[key];
          else delete attributes[key];
        });
        return attributes;
      };
    },
  };
}
