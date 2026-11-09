import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAlert } from 'dashboard/composables';
import AcharConfiraPage from '../pages/AcharConfiraPage.vue';

// #2694 — F2, "Com quem fica" pela fonte da API (sem ?demo=), com a API e o
// CRM falsos e os textos de verdade: o "Alterar" só aparece a quem gere funis
// (canManagePipelines); a lista vem do servidor para o funil escolhido e é
// refeita quando o funil muda; o owner_id vai no envio da folha e da gaveta; a
// recusa do servidor vira frase leiga.
const { rota, permissao } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return {
    rota: reactive({
      name: 'autonomia_prospecting_achar_busca',
      params: { accountId: '1', searchId: 9 },
      query: {},
    }),
    permissao: reactive({ gerirFunis: false }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 7, name: 'Lucas Andrade' },
  };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => false),
  };
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
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getSearch: vi.fn(),
    createCrmCards: vi.fn(),
    getCrmOwners: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];
Element.prototype.scrollIntoView = () => {};

const lead = id => ({
  id,
  name: `Empresa ${id}`,
  category: 'Escritório',
  priority_score: 90 - id,
  phone: `1199999000${id}`,
  whatsapp_verification_status: 'verified',
  whatsapp_url: `https://wa.me/551199999000${id}`,
  research: {
    company_status: 'confirmed',
    decision_status: 'confirmed',
    decision: { name: `Dona ${id}`, role: 'sócia' },
  },
});

const LUCAS = { id: 7, name: 'Lucas Andrade' };
const PAULA = { id: 8, name: 'Paula Ribeiro' };
// Paula vê o funil Vendas (4) e não vê o Revenda (5).
const DONOS = { 4: [LUCAS, PAULA], 5: [LUCAS] };

const abrir = async () => {
  const wrapper = mount(AcharConfiraPage, { attachTo: document.body });
  await vi.waitFor(() => {
    expect(wrapper.find('[aria-busy]').exists()).toBe(false);
  });
  await flushPromises();
  return wrapper;
};
const clicar = async (wrapper, seletor) => {
  await wrapper.find(seletor).trigger('click');
  await flushPromises();
};
const escolher = async (wrapper, texto) => {
  const cartao = wrapper
    .findAll('[data-escolha]')
    .find(item => item.text().includes(texto));
  await cartao.trigger('click');
  await flushPromises();
};
const abrirFolha = wrapper => clicar(wrapper, '[data-principal]');
const alterarPessoa = wrapper =>
  clicar(wrapper, '[data-com-quem] [data-alterar]');
const escolherPaula = async wrapper => {
  await alterarPessoa(wrapper);
  await escolher(wrapper, 'Paula Ribeiro');
  await clicar(wrapper, '[data-salvar-pessoa]');
};
const ultimoPedido = () =>
  AutonomiaProspectingAPI.createCrmCards.mock.calls.at(-1)[0];

describe('AcharConfiraPage: com quem fica (#2694)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
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
    AutonomiaProspectingAPI.getSearch.mockResolvedValue({
      data: {
        payload: {
          id: 9,
          query: 'Escritórios',
          location: 'Centro, Campinas, SP',
          location_label: 'Centro, Campinas, SP',
          radius: 3000,
          area_type: 'radius',
          results_count: 2,
          user_id: 7,
          leads: [lead(1), lead(2)],
        },
      },
    });
    AutonomiaProspectingAPI.getCrmOwners.mockImplementation(async id => ({
      data: { payload: DONOS[id] || [] },
    }));
    AutonomiaProspectingAPI.createCrmCards.mockImplementation(
      async ({ leadIds }) => ({
        data: {
          payload: {
            created: leadIds.map(id => ({ lead_id: id, card_id: 500 + id })),
            existing: [],
            failed: [],
          },
        },
      })
    );
    CrmKanbanAPI.getPipelines.mockResolvedValue({
      data: {
        payload: [
          { id: 4, name: 'Vendas', counts_as_sale: true },
          { id: 5, name: 'Revenda', counts_as_sale: true },
        ],
      },
    });
    CrmKanbanAPI.getStages.mockImplementation(async id => ({
      data: { payload: [{ id: id * 10, name: 'Novo contato' }] },
    }));
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('sem crm_manage_pipelines: "Com quem fica: você" sem "Alterar", sem pedir a lista e sem owner_id', async () => {
    const wrapper = await abrir();
    await abrirFolha(wrapper);

    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: você'
    );
    expect(wrapper.find('[data-com-quem] [data-alterar]').exists()).toBe(false);
    expect(AutonomiaProspectingAPI.getCrmOwners).not.toHaveBeenCalled();

    await clicar(wrapper, '[data-principal-folha]');

    expect(ultimoPedido().ownerId).toBeNull();
    expect(wrapper.find('[data-pronto]').text()).toContain(
      'Elas ficam com você'
    );
    wrapper.unmount();
  });

  it('com crm_manage_pipelines: a lista vem do funil, o owner_id vai na folha e o pronto diz com quem ficou', async () => {
    permissao.gerirFunis = true;
    const wrapper = await abrir();
    await abrirFolha(wrapper);

    expect(AutonomiaProspectingAPI.getCrmOwners).toHaveBeenLastCalledWith(4);
    await alterarPessoa(wrapper);
    const nomes = wrapper.findAll('[data-escolha]').map(item => item.text());
    expect(nomes).toHaveLength(2);
    expect(nomes[0]).toContain('Lucas Andrade (você)');
    expect(nomes[1]).toContain('Paula Ribeiro');
    await escolher(wrapper, 'Paula Ribeiro');
    await clicar(wrapper, '[data-salvar-pessoa]');

    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: Paula Ribeiro'
    );
    await clicar(wrapper, '[data-principal-folha]');

    expect(ultimoPedido()).toEqual(
      expect.objectContaining({ leadIds: [1, 2], pipelineId: 4, ownerId: 8 })
    );
    expect(wrapper.find('[data-pronto]').text()).toContain(
      'Elas ficam com Paula Ribeiro'
    );
    wrapper.unmount();
  });

  it('trocar de funil refaz a lista; quem não vê o funil novo volta para "você", com aviso', async () => {
    permissao.gerirFunis = true;
    const wrapper = await abrir();
    await abrirFolha(wrapper);
    await escolherPaula(wrapper);

    await clicar(wrapper, '[data-previa-funil] [data-alterar]');
    await escolher(wrapper, 'Revenda');
    await clicar(wrapper, '[data-salvar-destino]');

    expect(AutonomiaProspectingAPI.getCrmOwners).toHaveBeenLastCalledWith(5);
    expect(useAlert).toHaveBeenCalledWith(
      'Paula Ribeiro não vê este funil. As empresas vão ficar com você.'
    );
    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: você'
    );
    await clicar(wrapper, '[data-principal-folha]');
    expect(ultimoPedido()).toEqual(
      expect.objectContaining({ pipelineId: 5, ownerId: null })
    );
    wrapper.unmount();
  });

  it('troca de funil rápida: a resposta atrasada do funil anterior é descartada', async () => {
    permissao.gerirFunis = true;
    const wrapper = await abrir();
    await abrirFolha(wrapper);
    await escolherPaula(wrapper);
    let responderRevenda;
    AutonomiaProspectingAPI.getCrmOwners.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          responderRevenda = () => resolve({ data: { payload: DONOS[5] } });
        })
    );
    const trocarFunil = async nome => {
      await clicar(wrapper, '[data-previa-funil] [data-alterar]');
      await escolher(wrapper, nome);
      await clicar(wrapper, '[data-salvar-destino]');
    };

    await trocarFunil('Revenda');
    await trocarFunil('Vendas');
    responderRevenda();
    await flushPromises();

    expect(AutonomiaProspectingAPI.getCrmOwners).toHaveBeenLastCalledWith(4);
    expect(useAlert).not.toHaveBeenCalled();
    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: Paula Ribeiro'
    );
    await clicar(wrapper, '[data-principal-folha]');
    expect(ultimoPedido()).toEqual(
      expect.objectContaining({ pipelineId: 4, ownerId: 8 })
    );
    wrapper.unmount();
  });

  it('falha de rede ao refazer a lista volta para "você" sem dizer que a pessoa não vê o funil', async () => {
    permissao.gerirFunis = true;
    const wrapper = await abrir();
    await abrirFolha(wrapper);
    await escolherPaula(wrapper);
    AutonomiaProspectingAPI.getCrmOwners.mockRejectedValueOnce(
      new Error('Network Error')
    );

    await clicar(wrapper, '[data-previa-funil] [data-alterar]');
    await escolher(wrapper, 'Revenda');
    await clicar(wrapper, '[data-salvar-destino]');

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para carregar quem pode receber. As empresas vão ficar com você.'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      expect.stringContaining('não vê este funil')
    );
    expect(wrapper.find('[data-com-quem]').text()).toContain(
      'Com quem fica: você'
    );
    wrapper.unmount();
  });

  it('a recusa do servidor ao dono vira frase leiga na folha', async () => {
    permissao.gerirFunis = true;
    AutonomiaProspectingAPI.createCrmCards.mockRejectedValue({
      response: {
        status: 422,
        data: { code: 'prospecting.crm_send.owner_not_allowed', error: 'x' },
      },
    });
    const wrapper = await abrir();
    await abrirFolha(wrapper);
    await escolherPaula(wrapper);

    await clicar(wrapper, '[data-principal-folha]');

    expect(wrapper.find('[data-pronto]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'Essa pessoa não vê este funil. Escolha outra pessoa ou outro funil.'
    );
    wrapper.unmount();
  });

  it('a gaveta manda com o dono escolhido e diz com quem a empresa ficou', async () => {
    permissao.gerirFunis = true;
    const wrapper = await abrir();
    await clicar(wrapper, '[data-empresa="1"] [data-abrir-empresa]');
    await clicar(wrapper, '[data-principal-gaveta]');

    const alterar = wrapper.findAll('[data-alterar]');
    await alterar.at(-1).trigger('click');
    await flushPromises();
    await escolher(wrapper, 'Paula Ribeiro');
    await clicar(wrapper, '[data-salvar-pessoa]');
    await clicar(wrapper, '[data-mandar-um]');

    expect(ultimoPedido()).toEqual(
      expect.objectContaining({ leadIds: [1], ownerId: 8 })
    );
    await clicar(wrapper, '[data-fechar]');
    await clicar(wrapper, '[data-empresa="1"] [data-abrir-empresa]');
    expect(wrapper.find('[data-no-funil]').text()).toContain(
      'com Paula Ribeiro'
    );
    wrapper.unmount();
  });
});
