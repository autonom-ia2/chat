import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import AcharConfiraPage from '../pages/AcharConfiraPage.vue';

// #2693 — a lista pela fonte da API (sem ?demo=), com a API e o CRM falsos e
// os textos de verdade: a folha marca as mandadas e não reenvia; a gaveta
// reaberta de uma empresa mandada não oferece "Mandar / Não serve / Não quer";
// o evento ao vivo (prospecting.lead.updated) troca a empresa sem mock do
// useLeadLiveUpdates; sem telefone não há "Ligar"; "Buscar de novo" faz uma
// busca nova e a lista dela abre na rota NOVA.
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
  const valores = { getCurrentAccountId: 1, getCurrentUser: { id: 7 } };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
// Trocar o dono (#2694) é crm_manage_pipelines: aqui ninguém gere funis
// (o "Com quem fica" de verdade está em AcharConfiraPage.dono.spec.js).
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => false) }),
    };
  }
);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => false),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getSearch: vi.fn(),
    createSearch: vi.fn(),
    createCrmCards: vi.fn(),
    discardLeads: vi.fn(),
    refuseLeadConsent: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];
// O jsdom não rola a página; a lista rola até a empresa destacada.
Element.prototype.scrollIntoView = () => {};

const lead = (id, extra = {}) => ({
  id,
  name: `Empresa ${id}`,
  category: 'Escritório',
  neighborhood: 'Centro',
  priority_score: 90 - id,
  phone: `1199999000${id}`,
  whatsapp_verification_status: 'verified',
  whatsapp_url: `https://wa.me/551199999000${id}`,
  research: {
    company_status: 'confirmed',
    decision_status: 'confirmed',
    decision: { name: `Dona ${id}`, role: 'sócia' },
  },
  ...extra,
});

// Empresa 3: sem telefone e sem WhatsApp. Empresa 2: dono ainda procurando.
const LEADS = [
  lead(1),
  lead(2, { research: { company_status: 'researching' } }),
  lead(3, {
    phone: null,
    whatsapp_url: null,
    whatsapp_verification_status: 'not_whatsapp',
  }),
];

const busca = (extra = {}) => ({
  id: 9,
  query: 'Escritórios',
  location: 'Centro, Campinas, SP',
  location_label: 'Centro, Campinas, SP',
  location_place_id: 'p1',
  radius: 3000,
  requested_radius: 3000,
  area_type: 'radius',
  area_config: { radius: 3000 },
  requested_limit: 20,
  score_mode: 'general',
  advanced_filters: {},
  search_filters: { auto_expand_radius: true },
  results_count: LEADS.length,
  user_id: 7,
  user_name: 'Lucas',
  ...extra,
});

const responderBusca = (extra = {}, leads = LEADS) =>
  AutonomiaProspectingAPI.getSearch.mockResolvedValue({
    data: { payload: { ...busca(extra), leads } },
  });

const abrir = async () => {
  const wrapper = mount(AcharConfiraPage, {
    attachTo: document.body,
  });
  await vi.waitFor(() => {
    expect(wrapper.find('[aria-busy]').exists()).toBe(false);
  });
  await flushPromises();
  return wrapper;
};

const cartao = (wrapper, id) => wrapper.find(`[data-empresa="${id}"]`);
const abrirEmpresa = async (wrapper, id) => {
  await cartao(wrapper, id).find('[data-abrir-empresa]').trigger('click');
  await flushPromises();
};
const fecharGaveta = async wrapper => {
  await wrapper.find('[data-fechar]').trigger('click');
  await flushPromises();
};
const enviados = () =>
  AutonomiaProspectingAPI.createCrmCards.mock.calls.map(
    ([pedido]) => pedido.leadIds
  );

describe('AcharConfiraPage pela API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    rota.name = 'autonomia_prospecting_achar_busca';
    rota.params = { accountId: '1', searchId: 9 };
    rota.query = {};
    AutonomiaProspectingAPI.getSettings.mockResolvedValue({
      data: {
        payload: {
          can_send_to_crm: true,
          default_crm_pipeline_id: 4,
          default_crm_stage_id: 40,
        },
      },
    });
    CrmKanbanAPI.getPipelines.mockResolvedValue({
      data: { payload: [{ id: 4, name: 'Vendas', counts_as_sale: true }] },
    });
    CrmKanbanAPI.getStages.mockResolvedValue({
      data: { payload: [{ id: 40, name: 'Novo contato' }] },
    });
    responderBusca();
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('a folha marca created e existing como mandadas, mostra as que falharam e não reenvia', async () => {
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValueOnce({
      data: {
        payload: {
          created: [{ lead_id: 1, card_id: 501 }],
          existing: [{ lead_id: 2, card_id: 502 }],
          failed: [
            { lead_id: 3, reason_code: 'unexpected_error', message: 'x' },
          ],
        },
      },
    });
    const wrapper = await abrir();

    await wrapper.find('[data-principal]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-principal-folha]').trigger('click');
    await flushPromises();

    expect(enviados()).toEqual([[1, 2, 3]]);
    const pronto = wrapper.find('[data-pronto]').text();
    expect(pronto).toContain('Empresa 1 entrou no funil Vendas');
    expect(pronto).toContain('1 já estavam lá');
    // Frase neutra: invalid_data/not_found não se resolvem mandando de novo.
    expect(pronto).toContain('1 empresa não entrou no funil.');
    expect(pronto).toContain('Elas continuam na lista.');
    expect(pronto).not.toContain('problema do nosso lado');
    expect(pronto).not.toContain('mande de novo');

    await wrapper.find('[data-link-pronto]').trigger('click');
    await flushPromises();

    expect(cartao(wrapper, 1).find('[data-mandada]').text()).toBe(
      'Já está no funil Vendas'
    );
    expect(cartao(wrapper, 2).find('[data-mandada]').text()).toBe(
      'Já está num funil'
    );
    expect(cartao(wrapper, 3).find('[data-mandada]').exists()).toBe(false);

    // Reenvio: só a que falhou volta a ir; nada de "0 entraram".
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValueOnce({
      data: {
        payload: {
          created: [{ lead_id: 3, card_id: 503 }],
          existing: [],
          failed: [],
        },
      },
    });
    await wrapper.find('[data-principal]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-principal-folha]').trigger('click');
    await flushPromises();

    expect(enviados()[1]).toEqual([3]);
    expect(wrapper.find('[data-pronto]').text()).toContain(
      'Empresa 3 entrou no funil Vendas'
    );
    wrapper.unmount();
  });

  it('quando nenhuma nova entra, o pronto diz isso em vez de "0 entraram"', async () => {
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValueOnce({
      data: {
        payload: {
          created: [],
          existing: [
            { lead_id: 1, card_id: 501 },
            { lead_id: 2, card_id: 502 },
            { lead_id: 3, card_id: 503 },
          ],
          failed: [],
        },
      },
    });
    const wrapper = await abrir();

    await wrapper.find('[data-principal]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-principal-folha]').trigger('click');
    await flushPromises();

    const pronto = wrapper.find('[data-pronto]').text();
    expect(pronto).toContain('Nenhuma empresa nova entrou no funil Vendas');
    expect(pronto).not.toContain('0 empresas');
    wrapper.unmount();
  });

  it('a gaveta reaberta da empresa mandada diz onde ela está e não oferece "Mandar / Não serve / Não quer"', async () => {
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValueOnce({
      data: {
        payload: {
          created: [{ lead_id: 1, card_id: 501 }],
          existing: [],
          failed: [],
        },
      },
    });
    const wrapper = await abrir();

    await abrirEmpresa(wrapper, 1);
    await wrapper.find('[data-principal-gaveta]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-mandar-um]').trigger('click');
    await flushPromises();
    expect(enviados()).toEqual([[1]]);

    await fecharGaveta(wrapper);
    await abrirEmpresa(wrapper, 1);

    expect(wrapper.find('[data-no-funil]').text()).toBe(
      'No funil Vendas, etapa Novo contato, com você.'
    );
    expect(wrapper.find('[data-principal-gaveta]').text()).toBe('Ver o funil');
    expect(wrapper.find('[data-mais]').exists()).toBe(false);
    expect(wrapper.find('[data-mandar-um]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('o evento ao vivo troca a empresa na lista (dono achado)', async () => {
    const wrapper = await abrir();

    expect(wrapper.find('[data-barra]').exists()).toBe(true);
    expect(cartao(wrapper, 2).text()).not.toContain('Carla');

    emitter.emit(BUS_EVENTS.PROSPECTING_LEAD_UPDATED, {
      lead: lead(2, {
        research: {
          company_status: 'confirmed',
          decision_status: 'confirmed',
          decision: { name: 'Carla Souza', role: 'sócia' },
        },
      }),
    });
    await flushPromises();

    expect(cartao(wrapper, 2).find('[data-dono]').text()).toContain(
      'Carla Souza'
    );
    expect(wrapper.find('[data-barra]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('sem telefone e sem WhatsApp, a gaveta não oferece "Ligar"', async () => {
    const wrapper = await abrir();

    await abrirEmpresa(wrapper, 3);
    await wrapper.find('[data-mais]').trigger('click');
    const itens = wrapper.findAll('[role="menuitem"]').map(item => item.text());

    expect(itens).not.toContain('Ligar');
    expect(itens).not.toContain('Chamar no WhatsApp');
    expect(itens).toContain('Não serve');
    wrapper.unmount();
  });

  it('"Buscar de novo" (o Google parou) cria uma busca nova sem cache e abre a lista dela', async () => {
    responderBusca({ summary: { partial_results: true } });
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: { id: 78 } } },
    });
    const wrapper = await abrir();
    const faixa = wrapper
      .findAll('[role="status"]')
      .find(item => item.text().includes('Buscar de novo'));

    responderBusca({ id: 78 });
    await faixa.find('button').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expect.objectContaining({
        query: 'Escritórios',
        radius: 3000,
        fresh: true,
      })
    );
    expect(push).toHaveBeenLastCalledWith(
      expect.objectContaining({
        name: 'autonomia_prospecting_achar_nova',
        params: expect.objectContaining({ searchId: 78 }),
      })
    );
    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenLastCalledWith(78);
    wrapper.unmount();
  });

  it('"Procurar mais longe" (nada achado) dobra o raio da busca salva', async () => {
    responderBusca({ results_count: 0 }, []);
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: { id: 79 } } },
    });
    const wrapper = await abrir();
    const botao = wrapper
      .findAll('button')
      .find(item => item.text() === 'Procurar mais longe');

    await botao.trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expect.objectContaining({ radius: 6000, fresh: true })
    );
    expect(push).toHaveBeenLastCalledWith(
      expect.objectContaining({ name: 'autonomia_prospecting_achar_nova' })
    );
    wrapper.unmount();
  });

  it('lead descartado no servidor conta em "você tirou", fica em "Tiradas da lista" e a soma fecha ao recarregar', async () => {
    responderBusca({ results_count: 4 }, [
      lead(1),
      lead(5),
      lead(6, { status: 'discarded', discard_reason: 'Fora do perfil' }),
      lead(7, {
        crm_presence: { pipeline_name: 'Vendas', stage_name: 'Novo contato' },
      }),
    ]);
    const wrapper = await abrir();

    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenCalledWith(9);
    expect(wrapper.find('[data-fatos]').text()).toBe(
      '4 achadas · 2 vão · 1 você tirou · 1 fica de fora'
    );
    expect(cartao(wrapper, 6).find('[data-motivo-fora]').text()).toBe(
      'Tirada da lista: Fora do perfil'
    );
    expect(wrapper.text()).toContain('Tiradas da lista (1)');
    expect(wrapper.text()).toContain('Ficam de fora (1)');
    expect(wrapper.text()).not.toContain('outra busca');
    wrapper.unmount();
  });

  it('fora da demonstração, ?mandada= e ?empresa= do endereço não valem', async () => {
    rota.query = { mandada: '1', empresa: '2' };
    const wrapper = await abrir();

    expect(cartao(wrapper, 1).find('[data-mandada]').exists()).toBe(false);
    expect(wrapper.find('[data-principal-gaveta]').exists()).toBe(false);
    wrapper.unmount();
  });
});
