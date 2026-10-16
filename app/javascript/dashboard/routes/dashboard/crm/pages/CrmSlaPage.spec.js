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

const montar = ({
  role,
  customRoleId = null,
  keys = [],
  horarioUnico = false,
}) => {
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
      // #1619: a flag horario_unico_caixa, que o useHorarioUnicoCaixa lê da store da instância.
      mocks: {
        $store: {
          getters: {
            getCurrentAccountId: 9,
            'accounts/getAccount': () => ({ id: 9 }),
            'accounts/isFeatureEnabledonAccount': (_, flag) =>
              horarioUnico && flag === 'horario_unico_caixa',
          },
        },
      },
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
        CrmHorarioPessoas: { name: 'CrmHorarioPessoas', template: '<i />' },
        CrmHorarioCanais: { name: 'CrmHorarioCanais', template: '<i />' },
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
  pessoas: wrapper.findComponent({ name: 'CrmHorarioPessoas' }).exists(),
  canais: wrapper.findComponent({ name: 'CrmHorarioCanais' }).exists(),
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
      pessoas: false,
      canais: false,
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
      pessoas: false,
      canais: false,
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
      pessoas: false,
      canais: false,
    });
  });

  // #1619: com a flag horario_unico_caixa sai o calendário por caixa; entram as pessoas (só quem
  // edita calendário) e o horário dos canais (todos que veem a página).
  it('com horário único, o administrador vê pessoas e canais, sem o calendário por caixa', () => {
    const wrapper = montar({ role: 'administrator', horarioUnico: true });
    expect(tela(wrapper)).toMatchObject({
      politica: true,
      calendarios: false,
      pessoas: true,
      canais: true,
    });
    expect(wrapper.text()).toContain('HORARIO_DO_CANAL.SLA.DESCRICAO');
  });

  it('com horário único, sla_manage vê só o horário dos canais', () => {
    expect(
      tela(
        montar({
          role: 'agent',
          customRoleId: 7,
          keys: ['sla_manage'],
          horarioUnico: true,
        })
      )
    ).toMatchObject({ calendarios: false, pessoas: false, canais: true });
  });

  it('sem a flag, a descrição é a de hoje', () => {
    const wrapper = montar({ role: 'administrator' });
    expect(wrapper.text()).toContain('CRM_SLA.HEADER.DESCRIPTION');
  });
});
