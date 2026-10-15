// CRM › SLA (#1618): quem só tem sla_manage gerencia as políticas, mas a API dos
// calendários de atendimento responde só a administrador e crm_admin. A seção dos
// calendários fica fora para essa função, em vez de abrir com erro.
import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import CrmSlaPage from './CrmSlaPage.vue';

const getters = {};
const permissoes = ref([]);

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: vi.fn(),
    getters: { 'accounts/isFeatureEnabledonAccount': () => true },
  }),
  useMapGetter: key => getters[key],
}));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useHasCustomRolePermission: key =>
      computed(() => permissoes.value.includes(key)),
  };
});
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: () => Promise.resolve({ data: { payload: [] } }) },
}));

const montar = ({ role, keys = [] }) => {
  getters.getCurrentAccountId = ref(9);
  getters.getCurrentRole = ref(role);
  permissoes.value = keys;
  return shallowMount(CrmSlaPage);
};

const temCalendarios = wrapper =>
  wrapper.findComponent({ name: 'CrmInboxScheduleList' }).exists();

describe('CrmSlaPage', () => {
  it('função só com sla_manage vê as políticas, sem os calendários', () => {
    const wrapper = montar({ role: 'agent', keys: ['sla_manage'] });
    expect(wrapper.findComponent({ name: 'CrmSlaPolicyList' }).exists()).toBe(
      true
    );
    expect(temCalendarios(wrapper)).toBe(false);
  });

  it('função com crm_admin continua vendo os calendários', () => {
    expect(temCalendarios(montar({ role: 'agent', keys: ['crm_admin'] }))).toBe(
      true
    );
  });

  it('administrador continua vendo os calendários', () => {
    expect(temCalendarios(montar({ role: 'administrator' }))).toBe(true);
  });
});
