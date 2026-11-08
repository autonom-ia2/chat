import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAlert } from 'dashboard/composables';
import * as demoDados from '../demo/acharDemo';
import { criarFonte } from '../utils/acharFonte';
import ParaChamarPage from '../pages/ParaChamarPage.vue';

// #2697 — a fila "Para chamar" pela fonte da API (sem ?demo=), com a API e o
// CRM falsos e os textos de verdade: carregando, vazio e erro; a ordem do
// servidor; mandar ao funil com o bloco de sucesso dizendo etapa e dono (D13);
// "Não serve" e "Depois" gravam e o "Desfazer" volta; chamar abre o WhatsApp.
// E o contrato: o cartão da API tem todas as chaves do cartão da demonstração.
const { rota, push } = vi.hoisted(() => ({
  rota: {
    name: 'autonomia_prospecting_para_chamar',
    params: { accountId: '1' },
    query: {},
  },
  push: vi.fn(),
}));
const permissao = vi.hoisted(() => ({ buscar: true, gerirFunis: false }));

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 7, name: 'Ana' },
    'accounts/isFeatureEnabledonAccount': () => true,
  };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({
        canManagePipelines: computed(() => permissao.gerirFunis),
      }),
    };
  }
);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => permissao.buscar),
    usePermissionGranted: () => computed(() => true),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getQueue: vi.fn(),
    createCrmCards: vi.fn(),
    getCrmOwners: vi.fn(),
    discardLeads: vi.fn(),
    updateLead: vi.fn(),
    postponeQueueLead: vi.fn(),
    resumeQueueLead: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const lead = (id, extra = {}) => ({
  id,
  name: `Empresa ${id}`,
  category: 'Padaria',
  neighborhood: 'Centro',
  address: 'Rua Um, 1',
  priority_score: 90 - id,
  human_insight: 'Nota boa no Google.',
  phone: `1199999000${id}`,
  website: '',
  rating: 4.5,
  reviews_count: 20,
  whatsapp_verification_status: 'verified',
  whatsapp_url: `https://wa.me/551199999000${id}`,
  research: {
    company_status: 'confirmed',
    decision_status: 'confirmed',
    decision: { name: `Dona ${id}`, role: 'sócia' },
  },
  found_by_name: 'Lucas',
  ...extra,
});

const responderFila = (leads = [lead(1), lead(2)]) =>
  AutonomiaProspectingAPI.getQueue.mockResolvedValue({
    data: { payload: leads },
  });

const abrir = async () => {
  const wrapper = mount(ParaChamarPage, { attachTo: document.body });
  await flushPromises();
  await vi.waitFor(() => {
    expect(wrapper.find('[data-carregando]').exists()).toBe(false);
  });
  return wrapper;
};

const titulo = wrapper => wrapper.find('[data-cartao-fila] h2').text();
const clicar = async (wrapper, seletor) => {
  await wrapper.find(seletor).trigger('click');
  await flushPromises();
};
const botaoComTexto = (wrapper, texto) =>
  wrapper.findAll('button').find(botao => botao.text().includes(texto));

describe('ParaChamarPage pela API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    permissao.buscar = true;
    permissao.gerirFunis = false;
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
    responderFila();
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('mostra o carregando enquanto a fila não chega', async () => {
    AutonomiaProspectingAPI.getQueue.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(ParaChamarPage, { attachTo: document.body });
    await flushPromises();

    expect(wrapper.find('[data-carregando]').exists()).toBe(true);
    expect(wrapper.find('[data-cartao-fila]').exists()).toBe(false);
  });

  it('abre a primeira empresa na ordem do servidor, com quem achou e o funil do padrão', async () => {
    const wrapper = await abrir();

    expect(AutonomiaProspectingAPI.getQueue).toHaveBeenCalledTimes(1);
    expect(titulo(wrapper)).toBe('Empresa 1');
    expect(wrapper.text()).toContain('1 de 2');
    expect(wrapper.find('[data-achado-por]').text()).toBe('Achada por Lucas');
    expect(wrapper.find('[data-rodape]').text()).toContain(
      'Vai para o funil Vendas'
    );
    expect(wrapper.find('[data-principal]').text()).toBe('Mandar para o funil');
  });

  it('fila vazia diz isso e oferece achar empresas', async () => {
    responderFila([]);
    const wrapper = await abrir();

    expect(wrapper.text()).toContain('Ainda não há empresas para chamar.');
    expect(wrapper.find('[data-cartao-fila]').exists()).toBe(false);
  });

  it('erro ao abrir mostra a frase e "Tentar de novo" pede a fila outra vez', async () => {
    AutonomiaProspectingAPI.getQueue.mockRejectedValueOnce(new Error('rede'));
    const wrapper = await abrir();

    expect(wrapper.find('[data-erro-fila]').text()).toContain(
      'Não deu para abrir as empresas para chamar.'
    );
    await botaoComTexto(wrapper, 'Tentar de novo').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getQueue).toHaveBeenCalledTimes(2);
    expect(titulo(wrapper)).toBe('Empresa 1');
  });

  it('mandar ao funil usa o destino pronto, e o sucesso diz a etapa e com quem ficou (D13)', async () => {
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: { payload: { created: [{ lead_id: 1, card_id: 501 }] } },
    });
    const wrapper = await abrir();

    await clicar(wrapper, '[data-principal]');

    expect(AutonomiaProspectingAPI.createCrmCards).toHaveBeenCalledWith({
      leadIds: [1],
      pipelineId: 4,
      stageId: 40,
      ownerId: null,
    });
    expect(wrapper.find('[data-sucesso-fila]').text()).toContain(
      'Pronto. Empresa 1 está no funil Vendas.'
    );
    expect(wrapper.find('[data-etapa-e-dono]').text()).toBe(
      'Foi para a etapa Novo contato, com você.'
    );
    expect(wrapper.find('[data-principal]').text()).toBe('Chamar no WhatsApp');
  });

  it('envio recusado avisa e fica no cartão', async () => {
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: {
        payload: { failed: [{ lead_id: 1, reason_code: 'x', message: 'x' }] },
      },
    });
    const wrapper = await abrir();

    await clicar(wrapper, '[data-principal]');

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mandar. Nenhuma entrou.'
    );
    expect(wrapper.find('[data-sucesso-fila]').exists()).toBe(false);
    expect(titulo(wrapper)).toBe('Empresa 1');
  });

  it('"Não serve" descarta com o motivo e anda; "Desfazer" volta o lead a new_lead', async () => {
    AutonomiaProspectingAPI.discardLeads.mockResolvedValue({});
    AutonomiaProspectingAPI.updateLead.mockResolvedValue({});
    const wrapper = await abrir();

    await clicar(wrapper, '[data-nao-serve]');
    await clicar(wrapper, '[data-motivo="no_interest"]');

    expect(AutonomiaProspectingAPI.discardLeads).toHaveBeenCalledWith({
      leadIds: [1],
      reason: 'no_interest',
    });
    expect(titulo(wrapper)).toBe('Empresa 2');
    expect(wrapper.text()).toContain('Pronto. Ela saiu da fila.');

    await botaoComTexto(wrapper, 'Desfazer').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.updateLead).toHaveBeenCalledWith(1, {
      status: 'new_lead',
    });
    expect(titulo(wrapper)).toBe('Empresa 1');
  });

  it('"Depois" grava, anda e o "Desfazer" tira a marca', async () => {
    AutonomiaProspectingAPI.postponeQueueLead.mockResolvedValue({});
    AutonomiaProspectingAPI.resumeQueueLead.mockResolvedValue({});
    const wrapper = await abrir();

    await clicar(wrapper, '[data-depois]');

    expect(AutonomiaProspectingAPI.postponeQueueLead).toHaveBeenCalledWith(1);
    expect(wrapper.text()).toContain('Empresa 1 volta amanhã.');
    expect(titulo(wrapper)).toBe('Empresa 2');

    await botaoComTexto(wrapper, 'Desfazer').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.resumeQueueLead).toHaveBeenCalledWith(1);
    expect(titulo(wrapper)).toBe('Empresa 1');
  });

  it('"Depois" recusado pelo servidor avisa e não anda', async () => {
    AutonomiaProspectingAPI.postponeQueueLead.mockRejectedValue(new Error('x'));
    const wrapper = await abrir();

    await clicar(wrapper, '[data-depois]');

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para guardar. Tente de novo.'
    );
    expect(titulo(wrapper)).toBe('Empresa 1');
  });

  it('a última empresa leva ao fim do dia com a conta da passada', async () => {
    responderFila([lead(1)]);
    AutonomiaProspectingAPI.postponeQueueLead.mockResolvedValue({});
    const wrapper = await abrir();

    await clicar(wrapper, '[data-depois]');

    expect(wrapper.find('[data-fim-da-fila]').text()).toContain(
      '1 volta amanhã.'
    );
  });

  it('quem só vê não decide (sem "Não serve" e "Depois") e o principal chama', async () => {
    permissao.buscar = false;
    const abrirJanela = vi.spyOn(window, 'open').mockReturnValue(null);
    const wrapper = await abrir();

    expect(wrapper.find('[data-nao-serve]').exists()).toBe(false);
    expect(wrapper.find('[data-depois]').exists()).toBe(false);
    await clicar(wrapper, '[data-principal]');

    expect(abrirJanela).toHaveBeenCalledWith(
      'https://wa.me/5511999990001',
      '_blank',
      'noopener'
    );
    abrirJanela.mockRestore();
  });

  it('quem gere funis vê "Com quem fica" e manda com o dono escolhido', async () => {
    permissao.gerirFunis = true;
    AutonomiaProspectingAPI.getCrmOwners.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Ana' },
          { id: 8, name: 'Paula' },
        ],
      },
    });
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: { payload: { created: [{ lead_id: 1, card_id: 501 }] } },
    });
    const wrapper = await abrir();

    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: você'
    );
    await clicar(wrapper, '[data-com-quem] button');
    await botaoComTexto(wrapper, 'Paula').trigger('click');
    await clicar(wrapper, '[data-salvar-pessoa]');
    await clicar(wrapper, '[data-principal]');

    expect(AutonomiaProspectingAPI.createCrmCards).toHaveBeenCalledWith(
      expect.objectContaining({ ownerId: 8 })
    );
    expect(wrapper.find('[data-etapa-e-dono]').text()).toBe(
      'Foi para a etapa Novo contato, com Paula.'
    );
  });
});

describe('contrato da fila: demonstração × API', () => {
  it('o cartão da API tem todas as chaves do cartão da demonstração', async () => {
    const api = {
      getQueue: vi.fn().mockResolvedValue({ data: { payload: [lead(1)] } }),
    };
    const daApi = await criarFonte({ api, crm: {}, carregarDemo: null }).fila();
    const daDemo = await criarFonte({
      demo: 'fila',
      carregarDemo: () => Promise.resolve(demoDados),
    }).fila();

    expect(Object.keys(daApi)).toEqual(Object.keys(daDemo));
    const chavesDaApi = Object.keys(daApi.cartoes[0]);
    daDemo.cartoes.forEach(cartao => {
      expect(chavesDaApi).toEqual(expect.arrayContaining(Object.keys(cartao)));
      expect(Object.keys(daApi.cartoes[0].dono)).toEqual(
        expect.arrayContaining(Object.keys(cartao.dono))
      );
    });
    expect(daApi.cartoes[0]).toMatchObject({
      nome: 'Empresa 1',
      chance: 'boa',
      whatsapp: 'tem',
      achadoPor: 'Lucas',
    });
  });
});
