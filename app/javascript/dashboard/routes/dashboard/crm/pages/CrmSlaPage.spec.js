// CRM › SLA (#1618), por papel:
// - sla_manage: a API das políticas aceita escrita, então vê os botões; a API dos
//   calendários responde só a administrador e crm_admin, então a seção fica fora.
// - crm_admin sem sla_manage: vê as políticas só para leitura, sem os botões.
// - administrador: vê tudo.
// Os papéis passam pelas permissões reais (useCanManage e
// useHasCustomRolePermission), sem mock desses composables.
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import CrmSlaPage from './CrmSlaPage.vue';

const getters = {};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: vi.fn(),
    getters: { 'accounts/isFeatureEnabledonAccount': () => true },
  }),
  useMapGetter: key => getters[key],
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: () => Promise.resolve({ data: { payload: [] } }) },
}));

const passa = { template: '<div><slot /></div>' };

const montar = ({ role, customRoleId = null, keys = [] }) => {
  Object.assign(getters, {
    getCurrentAccountId: ref(9),
    getCurrentRole: ref(role),
    getCurrentCustomRoleId: ref(customRoleId),
    getCurrentUser: ref({ accounts: [{ id: 9, permissions: keys }] }),
    'sla/getSLA': ref([{ id: 1, name: 'Ouro', auto_apply: {} }]),
    'sla/getUIFlags': ref({ isFetching: false, isDeleting: false }),
  });
  return mount(CrmSlaPage, {
    global: {
      stubs: {
        BaseTable: {
          props: ['items', 'headers'],
          template:
            '<div><span class="cabecalho">{{ headers.join("|") }}</span><slot name="row" :items="items" /></div>',
        },
        BaseTableRow: passa,
        BaseTableCell: passa,
        Button: {
          props: ['label', 'icon'],
          template: '<button :data-icon="icon">{{ label }}</button>',
        },
        CrmSlaPolicyDialog: true,
        CrmInboxScheduleList: {
          name: 'CrmInboxScheduleList',
          template: '<i />',
        },
      },
    },
  });
};

const tela = wrapper => ({
  politica: wrapper.text().includes('Ouro'),
  adicionar: wrapper.text().includes('CRM_SLA.POLICIES.ADD'),
  editar: wrapper.find('[data-icon="i-lucide-pencil"]').exists(),
  apagar: wrapper.find('[data-icon="i-lucide-trash-2"]').exists(),
  colunaAcoes: wrapper
    .find('.cabecalho')
    .text()
    .includes('CRM_SLA.POLICIES.TABLE.ACTIONS'),
  calendarios: wrapper.findComponent({ name: 'CrmInboxScheduleList' }).exists(),
});

describe('CrmSlaPage por papel', () => {
  it('crm_admin sem sla_manage vê a lista, sem os botões', () => {
    expect(
      tela(montar({ role: 'agent', customRoleId: 7, keys: ['crm_admin'] }))
    ).toEqual({
      politica: true,
      adicionar: false,
      editar: false,
      apagar: false,
      colunaAcoes: false,
      calendarios: true,
    });
  });

  it('sla_manage vê os botões, sem a seção de calendários', () => {
    expect(
      tela(montar({ role: 'agent', customRoleId: 7, keys: ['sla_manage'] }))
    ).toEqual({
      politica: true,
      adicionar: true,
      editar: true,
      apagar: true,
      colunaAcoes: true,
      calendarios: false,
    });
  });

  it('administrador vê tudo', () => {
    expect(tela(montar({ role: 'administrator' }))).toEqual({
      politica: true,
      adicionar: true,
      editar: true,
      apagar: true,
      colunaAcoes: true,
      calendarios: true,
    });
  });
});
