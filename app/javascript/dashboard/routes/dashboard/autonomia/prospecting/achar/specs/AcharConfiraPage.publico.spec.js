import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import AcharConfiraPage from '../pages/AcharConfiraPage.vue';
import { criarFonte } from '../utils/acharFonte';
import { textosDoPronto } from '../utils/acharConfiraEstados';
import { LIMITE_DO_PUBLICO } from '../composables/useDonoDaLista';

// #2695 (F3b) — "Guardar para mandar mensagem" pela API: as empresas viram um
// Público de Campanhas (leads/audience). O pronto diz, em frase de leigo, quem
// ficou de fora e por quê, e "Criar a mensagem" abre a Nova campanha com o
// Público escolhido (?audience=). Sem campaign_manage ou com os Públicos
// desligados, o cartão nem aparece.
const { rota, push } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  const estado = reactive({
    name: 'autonomia_prospecting_achar_busca',
    params: { accountId: '1', searchId: 9 },
    query: {},
  });
  return {
    rota: estado,
    push: vi.fn(async destino => {
      estado.name = destino.name;
      estado.params = { ...destino.params };
      estado.query = { ...destino.query };
    }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 7 },
    'accounts/isFeatureEnabledonAccount': () => true,
  };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => false) }),
    };
  }
);
// Quem guarda tem campaign_manage; "Ver buscas de todos" não importa aqui.
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: chave => computed(() => chave === 'campaign_manage'),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getSearch: vi.fn(),
    createAudience: vi.fn(),
    createCrmCards: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];
Element.prototype.scrollIntoView = () => {};

const lead = (id, extra = {}) => ({
  id,
  name: `Empresa ${id}`,
  category: 'Escritório',
  neighborhood: 'Centro',
  priority_score: 90 - id,
  phone: `1199999000${id}`,
  whatsapp_verification_status: 'verified',
  research: {
    company_status: 'confirmed',
    decision_status: 'confirmed',
    decision: { name: `Dona ${id}`, role: 'sócia' },
  },
  ...extra,
});

// Empresa 3 não tem telefone nem e-mail: nem vai no pedido.
const LEADS = [lead(1), lead(2), lead(3, { phone: null })];

const PUBLICOS_LIGADOS = {
  CAMPAIGN_JOURNEY_ENABLED: 'true',
  CAMPAIGN_IMPORT_ENABLED: 'true',
};

const abrir = async () => {
  const wrapper = mount(AcharConfiraPage, { attachTo: document.body });
  await vi.waitFor(() => {
    expect(wrapper.find('[aria-busy]').exists()).toBe(false);
  });
  await flushPromises();
  return wrapper;
};

const guardar = async wrapper => {
  await wrapper.find('[data-principal]').trigger('click');
  await flushPromises();
  await wrapper.find('[data-escolha-lista]').trigger('click');
  await flushPromises();
  await wrapper.find('[data-principal-folha]').trigger('click');
  await flushPromises();
};

describe('AcharConfiraPage: guardar para mandar mensagem', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    window.globalConfig = { ...PUBLICOS_LIGADOS };
    rota.name = 'autonomia_prospecting_achar_busca';
    rota.params = { accountId: '1', searchId: 9 };
    rota.query = {};
    AutonomiaProspectingAPI.getSettings.mockResolvedValue({
      data: { payload: { can_send_to_crm: true } },
    });
    CrmKanbanAPI.getPipelines.mockResolvedValue({ data: { payload: [] } });
    AutonomiaProspectingAPI.getSearch.mockResolvedValue({
      data: {
        payload: {
          id: 9,
          query: 'Escritórios',
          location: 'Centro, Campinas, SP',
          location_label: 'Centro, Campinas, SP',
          results_count: LEADS.length,
          user_id: 7,
          leads: LEADS,
        },
      },
    });
  });
  afterEach(() => {
    document.body.innerHTML = '';
    delete window.globalConfig;
  });

  it('guarda o Público, diz quem ficou de fora e abre a Nova campanha com ele', async () => {
    AutonomiaProspectingAPI.createAudience.mockResolvedValueOnce({
      data: {
        payload: {
          audience: { id: 55, name: 'Escritórios', count: 1 },
          entered_lead_ids: [1],
          left_out: [{ lead_id: 2, reason_code: 'opt_out', message: 'x' }],
        },
      },
    });
    const wrapper = await abrir();

    await guardar(wrapper);

    const [pedido] = AutonomiaProspectingAPI.createAudience.mock.calls[0];
    expect(pedido.leadIds).toEqual([1, 2]);
    expect(pedido.name).toBeTruthy();
    const pronto = wrapper.find('[data-pronto]').text();
    expect(pronto).toContain('A lista para mensagem está guardada');
    expect(pronto).toContain(
      '1 pediu para não receber mensagem e ficou de fora.'
    );

    await wrapper.find('[data-rodape] button').trigger('click');
    await flushPromises();

    expect(push).toHaveBeenLastCalledWith({
      name: 'campaigns_journey_new',
      params: { accountId: '1' },
      query: { audience: '55' },
    });
    wrapper.unmount();
  });

  it('quando ninguém pode receber, a folha diz isso e não guarda nada', async () => {
    AutonomiaProspectingAPI.createAudience.mockRejectedValueOnce({
      response: {
        data: {
          code: 'prospecting.audience.no_rows',
          left_out: [{ lead_id: 1, reason_code: 'opt_out' }],
        },
      },
    });
    const wrapper = await abrir();

    await guardar(wrapper);

    expect(wrapper.find('[data-pronto]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      ptBR.PROSPECTING_ACHAR.FOLHA.ERRO_LISTA_NINGUEM
    );
    expect(wrapper.find('[data-fora-do-erro]').text()).toBe(
      '1 pediu para não receber mensagem e ficou de fora.'
    );
    wrapper.unmount();
  });

  it('acima do teto, a folha diz o máximo e não chama o servidor', async () => {
    const muitos = Array.from({ length: LIMITE_DO_PUBLICO + 1 }, (_, i) =>
      lead(i + 1)
    );
    AutonomiaProspectingAPI.getSearch.mockResolvedValue({
      data: {
        payload: {
          id: 9,
          query: 'Escritórios',
          location_label: 'Centro, Campinas, SP',
          results_count: muitos.length,
          user_id: 7,
          leads: muitos,
        },
      },
    });
    const wrapper = await abrir();

    await guardar(wrapper);

    expect(AutonomiaProspectingAPI.createAudience).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      `Guarde até ${LIMITE_DO_PUBLICO} empresas por vez.`
    );
    wrapper.unmount();
  });

  it('com os Públicos desligados, a folha só oferece o funil', async () => {
    window.globalConfig = {};
    const wrapper = await abrir();

    await wrapper.find('[data-principal]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-escolha-lista]').exists()).toBe(false);
    expect(wrapper.find('[data-previa-funil]').exists()).toBe(true);
    wrapper.unmount();
  });
});

describe('fonte do Público', () => {
  it('a recusa do servidor vem com o código e quem ficou de fora', async () => {
    const api = {
      createAudience: vi.fn().mockRejectedValue({
        response: {
          data: {
            code: 'prospecting.audience.foreign_contact',
            left_out: [{ lead_id: 4, reason_code: 'no_channel' }],
          },
        },
      }),
    };
    const fonte = criarFonte({ api, crm: {} });

    await expect(fonte.guardarLista({ nome: 'X', ids: [4] })).rejects.toEqual(
      expect.objectContaining({
        codigo: 'prospecting.audience.foreign_contact',
        fora: [{ id: 4, motivo: 'no_channel' }],
      })
    );
  });

  it('a demonstração não chama a API e devolve um Público de exemplo com um de fora', async () => {
    const api = { createAudience: vi.fn() };
    const fonte = criarFonte({
      demo: 'folha-lista',
      carregarDemo: () => Promise.resolve({}),
      api,
      atraso: 0,
    });

    const guardado = await fonte.guardarLista({ nome: 'X', ids: [1, 2] });

    expect(api.createAudience).not.toHaveBeenCalled();
    expect(guardado).toEqual({
      publicoId: 9001,
      nome: 'X',
      n: 1,
      fora: [{ id: 2, motivo: 'no_channel' }],
    });
  });

  it('demonstração e API devolvem o Público com as mesmas chaves', async () => {
    const api = {
      createAudience: vi.fn().mockResolvedValue({
        data: {
          payload: {
            audience: { id: 55, name: 'X', count: 1 },
            entered_lead_ids: [1],
            left_out: [{ lead_id: 2, reason_code: 'opt_out', message: 'x' }],
          },
        },
      }),
    };
    const pedido = { nome: 'X', ids: [1, 2] };
    const daApi = await criarFonte({ api, crm: {} }).guardarLista(pedido);
    const daDemo = await criarFonte({
      demo: 'folha-lista',
      carregarDemo: () => Promise.resolve({}),
      atraso: 0,
    }).guardarLista(pedido);

    expect(Object.keys(daDemo).sort()).toEqual(Object.keys(daApi).sort());
    expect(Object.keys(daDemo.fora[0]).sort()).toEqual(
      Object.keys(daApi.fora[0]).sort()
    );
  });

  it('o pronto junta quem ficou de fora por motivo, em frase de leigo', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: ptBR },
    });
    const { detalhes } = textosDoPronto(i18n.global.t, {
      pronto: {
        tipo: 'lista',
        n: 3,
        fora: [
          { id: 1, motivo: 'no_channel' },
          { id: 2, motivo: 'no_channel' },
          { id: 3, motivo: 'unexpected_error' },
          { id: 4, motivo: 'same_contact' },
        ],
      },
      nomeLista: 'Escritórios',
    });

    expect(detalhes).toContain(
      '2 não têm celular nem e-mail e ficaram de fora.'
    );
    expect(detalhes).toContain('Não deu para guardar 1. Tente de novo.');
    expect(detalhes).toContain(
      '1 é a mesma pessoa de outra empresa da lista: entrou uma vez só.'
    );
  });
});
