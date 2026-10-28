import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import { CARLA } from './quemMonta';

// Montagem comum das specs da conversa guiada (#2308): i18n pt_BR e a store que o usePeopleAccess lê, com as flags
// da conta (crm_numeros_lentes muda o que quem fica sem função vê).
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
  flags = [],
  actions = {},
  caixas = [],
} = {}) =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => (giver.isAdmin ? 'administrator' : 'agent'),
      getCurrentCustomRoleId: () => giver.customRoleId,
      getCurrentUser: () => ({
        id: giver.userId,
        accounts: [{ id: 1, permissions: giver.permissions }],
      }),
      'accounts/getAccount': () => () => ({ id: 1 }),
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        flags.includes(flag),
      'customRole/getCustomRoles': () => funcoes,
      'agents/getAgents': () => agentes,
      'inboxes/getInboxes': () => caixas,
    },
    actions: {
      'customRole/getCustomRole': vi.fn(),
      'agents/get': vi.fn(),
      ...actions,
    },
  });

export const global = (store = loja()) => ({
  plugins: [store, i18n()],
  stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
});

// O jsdom não tem showModal: o espião registra a abertura do diálogo da casa; soltar() tira o espião.
export const espiarDialogo = () => {
  const mostrar = vi.fn();
  HTMLDialogElement.prototype.showModal = mostrar;
  return {
    mostrar,
    soltar: () => delete HTMLDialogElement.prototype.showModal,
  };
};
