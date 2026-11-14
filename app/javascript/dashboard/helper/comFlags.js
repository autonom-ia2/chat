import store from 'dashboard/store';

// Guarda de rota por flags da conta (Seus posts #2304, IA cuida dos comentários #2212). Link direto / F5: o guarda
// roda antes de a store ter a conta. Carrega a conta antes de decidir (mesmo cuidado de booking.routes.js); sem conta,
// ou com as flags fora do que `vale` pede, vai para home.
const ligadaNa = accountId => flag =>
  store.getters['accounts/isFeatureEnabledonAccount'](accountId, flag);

// `false` quando a conta não está na store e não deu para carregar.
const contaCarregada = async accountId => {
  if (store.getters['accounts/getAccount'](accountId)?.id) return true;
  try {
    await store.dispatch('accounts/get');
    return true;
  } catch {
    return false;
  }
};

const guarda = vale => async (to, _from, next) => {
  const accountId = Number(to.params.accountId);
  const liberada =
    (await contaCarregada(accountId)) && vale(ligadaNa(accountId), to);
  if (liberada) next();
  else next({ name: 'home', params: to.params });
};

// Para o guarda que escolhe o destino em vez de barrar (a importação de contatos que leva a "Trazer minha lista",
// #2896): carrega a conta com o mesmo cuidado e diz se todas as flags estão ligadas. Conta que não carrega: `false`.
export const contaTemFlags = async (accountId, flags) =>
  (await contaCarregada(Number(accountId))) &&
  flags.every(ligadaNa(Number(accountId)));

// A mesma pergunta para quem já está dentro do painel (a conta já está na store): sem esperar.
export const contaJaTemFlags = (accountId, flags) =>
  flags.every(ligadaNa(Number(accountId)));

// Todas as flags ligadas.
export const comFlags = (...flags) => guarda(ligada => flags.every(ligada));

// Todas de `todas` e ao menos uma de `algumas` (as flags por rede do anúncio, como o servidor confere).
export const comFlagsEAlguma = (todas, algumas) =>
  guarda(ligada => todas.every(ligada) && algumas.some(ligada));

// As flags que a rota pede, conforme o endereço (a rede do perfil em ?perfil=, #2520). Sem flags (rede desconhecida):
// home.
export const comFlagsDaRota = flagsDe =>
  guarda((ligada, to) => {
    const flags = flagsDe(to);
    return Boolean(flags) && flags.every(ligada);
  });
