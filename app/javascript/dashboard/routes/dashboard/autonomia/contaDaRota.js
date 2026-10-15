import store from 'dashboard/store';

// Link direto / F5: o guarda roda antes de a store ter a conta, e o getter volta
// vazio; sem esperar, a rota mandava para home com o recurso ligado (Cotação em
// 03/09, Prospecção e Agentes na #675, Prospecção › Configurações na #1618).
// Carrega a conta antes de decidir. Se ela não carregar, o guarda segue sem conta
// e redireciona, como antes.
export const contaDaRota = async to => {
  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);
  if (account?.id) return account;
  try {
    await store.dispatch('accounts/get');
  } catch {
    return null;
  }
  return store.getters['accounts/getAccount'](accountId);
};

// Prospecção é ligada por conta (`autonomia_prospecting_enabled`); com a conta
// desligada, a rota vai para home, como o 404 do backend.
export const ensureProspectingEnabled = async (to, _from, next) => {
  const account = await contaDaRota(to);

  if (account?.autonomia_prospecting_enabled === true) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};
