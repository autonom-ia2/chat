import store from 'dashboard/store';

// Guarda de rota por flags da conta (Seus posts #2304, IA cuida dos comentários #2212). Link direto / F5: o guarda
// roda antes de a store ter a conta. Carrega a conta antes de decidir (mesmo cuidado de booking.routes.js); sem conta,
// ou com as flags fora do que `vale` pede, vai para home.
const guarda = vale => async (to, _from, next) => {
  const accountId = Number(to.params.accountId);
  const ligada = flag =>
    store.getters['accounts/isFeatureEnabledonAccount'](accountId, flag);
  if (!store.getters['accounts/getAccount'](accountId)?.id) {
    try {
      await store.dispatch('accounts/get');
    } catch {
      next({ name: 'home', params: to.params });
      return;
    }
  }
  if (vale(ligada)) next();
  else next({ name: 'home', params: to.params });
};

// Todas as flags ligadas.
export const comFlags = (...flags) => guarda(ligada => flags.every(ligada));

// Todas de `todas` e ao menos uma de `algumas` (as flags por rede do anúncio, como o servidor confere).
export const comFlagsEAlguma = (todas, algumas) =>
  guarda(ligada => todas.every(ligada) && algumas.some(ligada));
