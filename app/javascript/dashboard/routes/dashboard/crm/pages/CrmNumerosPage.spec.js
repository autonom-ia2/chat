import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import CrmNumerosAPI from 'dashboard/api/crmNumeros';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmNumerosPage from './CrmNumerosPage.vue';

// CRM › Números (#1897): nada pede números nem relatórios da equipe antes de a
// conta chegar, o agente sem função com a flag nunca pede os relatórios, e se a
// conta não vier a página mostra o erro com "Tentar de novo" (não fica em branco).
const estado = reactive({
  contaCarregada: true,
  flag: true,
  papel: 'agent',
  funcao: null,
  chaves: [],
  contaNaProximaBusca: false,
});
const dispatch = vi.fn(async () => {
  if (estado.contaNaProximaBusca) estado.contaCarregada = true;
});
const replace = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {}, params: { accountId: 1 } }),
  useRouter: () => ({ replace }),
}));
vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('pt-BR') }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({}) }),
}));
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: chave =>
    ({
      getCurrentAccountId: ref(1),
      getCurrentUser: ref({
        accounts: [{ id: 1, permissions: estado.chaves }],
      }),
      getCurrentRole: ref(estado.papel),
      getCurrentCustomRoleId: ref(estado.funcao),
      'accounts/isFeatureEnabledonAccount': ref(() => estado.flag),
      'accounts/getAccount': ref(() =>
        estado.contaCarregada ? { id: 1, features: {} } : {}
      ),
    })[chave],
}));
vi.mock('dashboard/api/crmNumeros', () => ({
  default: {
    show: vi.fn(() =>
      Promise.resolve({ data: { vazio: true, podeCriarFunil: false } })
    ),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getReportPipelines: vi.fn(() => Promise.resolve({ data: [] })) },
}));
// O painel da equipe de verdade pede crm/reports/pipelines ao montar
// (CrmDashboardPage.vue, getReportPipelines); o substituto faz o mesmo.
vi.mock('./CrmDashboardPage.vue', async () => {
  const { defineComponent, h, onMounted } = await import('vue');
  const { default: api } = await import('dashboard/api/crmKanban');
  return {
    default: defineComponent({
      setup(_, { slots }) {
        onMounted(() => api.getReportPipelines());
        return () => h('div', { 'data-painel-equipe': '' }, slots.topo?.());
      },
    }),
  };
});

// Cada teste desmonta a página: o estado é reativo e uma página viva de um teste
// reagiria às mudanças do seguinte.
let montadas = [];
afterEach(() => {
  montadas.forEach(wrapper => wrapper.unmount());
  montadas = [];
});

const montar = () => {
  const wrapper = mount(CrmNumerosPage, {
    global: {
      stubs: {
        CrmVistasNumeros: true,
        NumerosComoContamos: true,
        RouterLink: true,
        Banner: {
          emits: ['action'],
          template:
            '<div data-numeros-aviso-admin><button data-entendi @click="$emit(\'action\')" /><slot /></div>',
        },
        ResultsToggle: true,
      },
    },
  });
  montadas.push(wrapper);
  return wrapper;
};

describe('CrmNumerosPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(estado, {
      contaCarregada: true,
      flag: true,
      papel: 'agent',
      funcao: null,
      chaves: [],
      contaNaProximaBusca: false,
    });
  });

  it('agente sem função com a flag: abre "Só eu" e nunca pede os relatórios da equipe', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(CrmNumerosAPI.show).toHaveBeenCalledTimes(1);
    expect(CrmKanbanAPI.getReportPipelines).not.toHaveBeenCalled();
    expect(wrapper.find('[data-painel-equipe]').exists()).toBe(false);
    expect(replace).not.toHaveBeenCalled();
  });

  it('sem a flag, o agente sem função segue no painel da equipe (como antes)', async () => {
    estado.flag = false;
    montar();
    await flushPromises();
    expect(CrmKanbanAPI.getReportPipelines).toHaveBeenCalledTimes(1);
    expect(CrmNumerosAPI.show).not.toHaveBeenCalled();
  });

  it('antes da conta chegar: carregando, sem pedir nada e sem desviar', async () => {
    estado.contaCarregada = false;
    estado.contaNaProximaBusca = true;
    const wrapper = montar();
    expect(wrapper.find('[data-numeros-carregando]').exists()).toBe(true);
    expect(CrmNumerosAPI.show).not.toHaveBeenCalled();
    expect(CrmKanbanAPI.getReportPipelines).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('accounts/get', {
      accountId: 1,
      silent: true,
    });
  });

  it('conta não veio: mostra o erro; "Tentar de novo" busca e abre "Só eu"', async () => {
    estado.contaCarregada = false;
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-numeros-erro]').exists()).toBe(true);
    expect(CrmNumerosAPI.show).not.toHaveBeenCalled();
    expect(CrmKanbanAPI.getReportPipelines).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();

    estado.contaNaProximaBusca = true;
    await wrapper.find('[data-numeros-tentar]').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-numeros-erro]').exists()).toBe(false);
    expect(CrmNumerosAPI.show).toHaveBeenCalledTimes(1);
    expect(CrmKanbanAPI.getReportPipelines).not.toHaveBeenCalled();
  });

  it('quem não abre Números (função sem chave do CRM) vai para o Kanban', async () => {
    Object.assign(estado, { funcao: 7, chaves: ['conversation_manage'] });
    montar();
    await flushPromises();
    expect(replace).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      params: { accountId: 1 },
    });
    expect(CrmNumerosAPI.show).not.toHaveBeenCalled();
    expect(CrmKanbanAPI.getReportPipelines).not.toHaveBeenCalled();
  });

  it('administrador com a flag: abre na Equipe, com o aviso', async () => {
    estado.papel = 'administrator';
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-painel-equipe]').exists()).toBe(true);
    expect(wrapper.find('[data-numeros-aviso-admin]').exists()).toBe(true);
    expect(replace).not.toHaveBeenCalled();
  });

  it('função com "Visualizar relatórios do CRM" também vê o aviso; o agente sem função, não', async () => {
    Object.assign(estado, { funcao: 7, chaves: ['crm_view_reports'] });
    const gestor = montar();
    await flushPromises();
    expect(gestor.find('[data-painel-equipe]').exists()).toBe(true);
    expect(gestor.find('[data-numeros-aviso-admin]').exists()).toBe(true);

    Object.assign(estado, { funcao: null, chaves: [] });
    const agente = montar();
    await flushPromises();
    expect(agente.find('[data-numeros-aviso-admin]').exists()).toBe(false);
  });

  it('"Entendi" fecha o aviso e grava no navegador', async () => {
    window.localStorage.removeItem('crm-numeros-aviso-equipe-1');
    estado.papel = 'administrator';
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-entendi]').trigger('click');
    expect(wrapper.find('[data-numeros-aviso-admin]').exists()).toBe(false);
    expect(window.localStorage.getItem('crm-numeros-aviso-equipe-1')).toBe('1');

    const deNovo = montar();
    await flushPromises();
    expect(deNovo.find('[data-numeros-aviso-admin]').exists()).toBe(false);
    window.localStorage.removeItem('crm-numeros-aviso-equipe-1');
  });
});
