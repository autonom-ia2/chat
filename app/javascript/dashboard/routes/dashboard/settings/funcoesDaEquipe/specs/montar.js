import { reactive } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import { CARLA } from './quemMonta';

// Montagem comum das specs da conversa guiada (#2308): i18n pt_BR e a store que o usePeopleAccess lê, com as flags
// da conta (custom_roles ligada por padrão; crm_numeros_lentes muda o que quem fica sem função vê).
export const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: { pt_BR: ptBR },
    missingWarn: false,
    fallbackWarn: false,
  });

export const loja = ({
  giver = CARLA,
  funcoes = [],
  agentes = [],
  flags = ['custom_roles'],
  actions = {},
  caixas = [],
} = {}) => {
  // Funções e pessoas reativas, como na store de verdade: uma recarga que muda a lista recalcula a tela (rodada 9).
  // Quem quer mexer na lista depois de montar passa a própria lista reativa (reactive devolve o mesmo proxy).
  const funcoesVivas = reactive(funcoes);
  const agentesVivos = reactive(agentes);
  return createStore({
    // Quem monta como a store guarda: SET_CURRENT_USER (o mesmo commit do auth) troca, pela ação setCurrentUser.
    state: () => ({
      currentUser: {
        id: giver.userId,
        accounts: [{ id: 1, permissions: giver.permissions }],
      },
    }),
    mutations: {
      SET_CURRENT_USER: (state, usuario) => {
        state.currentUser = usuario;
      },
    },
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => (giver.isAdmin ? 'administrator' : 'agent'),
      getCurrentCustomRoleId: () => giver.customRoleId,
      getCurrentUser: state => state.currentUser,
      'accounts/getAccount': () => () => ({ id: 1 }),
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        flags.includes(flag),
      'customRole/getCustomRoles': () => funcoesVivas,
      'agents/getAgents': () => agentesVivos,
      'inboxes/getInboxes': () => caixas,
    },
    actions: {
      'customRole/getCustomRole': vi.fn(),
      'agents/get': vi.fn(),
      validityCheck: vi.fn(),
      setCurrentUser: ({ commit }, usuario) =>
        commit('SET_CURRENT_USER', usuario),
      ...actions,
    },
  });
};

export const global = (store = loja()) => ({
  plugins: [store, i18n()],
  stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
});

// O jsdom não tem showModal nem close: o espião registra a abertura (e, com `marcarAberto`, põe o atributo open, como
// o navegador) e o fechamento do diálogo da casa. soltar() tira os espiões; quem usa chama no afterEach, para um teste
// que falha não deixar o espião para o seguinte.
export const espiarDialogo = ({ marcarAberto = false } = {}) => {
  const mostrar = vi.fn(function abrirModal() {
    if (marcarAberto) this.setAttribute('open', '');
  });
  const fechar = vi.fn();
  HTMLDialogElement.prototype.showModal = mostrar;
  HTMLDialogElement.prototype.close = fechar;
  return {
    mostrar,
    fechar,
    soltar: () => {
      delete HTMLDialogElement.prototype.showModal;
      delete HTMLDialogElement.prototype.close;
    },
  };
};
