import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import FuncoesDaEquipePage from '../FuncoesDaEquipePage.vue';

// Montagem da lista de funções (#2308, especificação 5.A e 5.E), comum à spec da lista e à do apagar. Os vi.mock
// (rotas, auth, alerta) ficam em cada spec.
export const ATENDENTE = {
  id: 1,
  name: 'Atendente',
  description: 'Quem atende o WhatsApp no dia a dia.',
  permissions: [
    'conversation_participating_manage',
    'conversation_unassigned_manage',
    'contact_view',
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
  ],
};
export const FINANCEIRO = {
  id: 2,
  name: 'Financeiro',
  permissions: ['financial_view', 'report_manage'],
};
export const AGENTES = [
  { id: 10, name: 'Ana', role: 'agent', custom_role_id: 1 },
  { id: 11, name: 'Bia', role: 'agent', custom_role_id: null },
  { id: 12, name: 'Caio', role: 'agent', custom_role_id: null },
  { id: 13, name: 'Duda', role: 'administrator', custom_role_id: null },
];

// Carla: não administradora, monta funções e tem as chaves do Atendente; Pessoas só quando o teste pede.
export const recarregar = vi.fn();

export const montar = async ({
  funcoes = [ATENDENTE, FINANCEIRO],
  admin = true,
  pessoas = false,
  falha = false,
  plano = true,
  apagar = vi.fn(),
  lentes = false,
  pessoasDaConta = vi.fn(),
  agentes = AGENTES,
} = {}) => {
  const permissoes = [
    'custom_role_manage',
    ...ATENDENTE.permissions,
    ...(pessoas ? ['people_manage'] : []),
  ];
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => (admin ? 'administrator' : 'agent'),
      getCurrentCustomRoleId: () => (admin ? null : 99),
      getCurrentUser: () => ({
        id: 50,
        accounts: [{ id: 1, permissions: admin ? [] : permissoes }],
      }),
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        flag === 'crm_numeros_lentes' ? lentes : plano,
      'customRole/getCustomRoles': () => funcoes,
      'customRole/getUIFlags': () => ({
        fetchingList: false,
        fetchingListFailed: falha,
      }),
      'agents/getAgents': () => agentes,
    },
    actions: {
      'customRole/getCustomRole': recarregar,
      'customRole/deleteCustomRole': apagar,
      'agents/get': pessoasDaConta,
    },
  });
  const wrapper = mount(FuncoesDaEquipePage, {
    attachTo: document.body,
    global: {
      plugins: [
        store,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      stubs: {
        Avatar: true,
        GavetaDaFuncao: true,
        PaywallDasFuncoes: { template: '<div data-paywall />' },
        TeleportWithDirection: { template: '<div><slot /></div>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

export const pedirApagar = async cartao => {
  await cartao.find('[data-mais]').trigger('click');
  await cartao.find('[data-acao="apagar"]').trigger('click');
};
export const dialogo = wrapper => wrapper.find('dialog');
