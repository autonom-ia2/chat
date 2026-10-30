import store from 'dashboard/store';

// Guarda de rota por flags da conta (Seus posts #2304, IA cuida dos comentários #2212). Link direto / F5: o guarda
// roda antes de a store ter a conta. Carrega a conta antes de decidir (mesmo cuidado de booking.routes.js); sem conta,
// ou com alguma flag desligada, vai para home.
export const comFlags =
  (...flags) =>
  async (to, _from, next) => {
    const accountId = Number(to.params.accountId);
    const ligada = () =>
      flags.every(flag =>
        store.getters['accounts/isFeatureEnabledonAccount'](accountId, flag)
      );
    if (!store.getters['accounts/getAccount'](accountId)?.id) {
      try {
        await store.dispatch('accounts/get');
      } catch {
        next({ name: 'home', params: to.params });
        return;
      }
    }
    if (ligada()) next();
    else next({ name: 'home', params: to.params });
  };
