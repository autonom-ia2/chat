import { mount, flushPromises } from '@vue/test-utils';
import AutomationAPI from 'dashboard/api/automation';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import LivreListaPage from '../pages/LivreListaPage.vue';
import LivreConfirmarLigar from '../components/LivreConfirmarLigar.vue';

// #2414 F5 — a lista única: as novas (em frase pelo catálogo) e as do jeito
// antigo, que abrem na tela de hoje. Ligar leva a versão vista e a linha
// continua com a frase (a resposta de ligar não traz a receita).
const { routerPush, config, caixas, porta, conta } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  config: { crmKanbanEnabled: false },
  caixas: [{ id: 5, name: 'WhatsApp Vendas' }],
  porta: {},
  conta: { passosNovos: false },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    t: (chave, valores) => {
      if (valores?.caixa) return `${valores.frase} → ${valores.caixa}`;
      return valores?.n ? `${chave}:${valores.n}` : chave;
    },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
  useRouter: () => ({ push: routerPush }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => conta.passosNovos }),
}));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref } = await import('vue');
  porta.podeMudar = ref(true);
  return { useCanManage: () => porta.podeMudar };
});
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: getter => {
      if (getter === 'globalConfig/get') return ref(config);
      return ref(getter === 'inboxes/getInboxes' ? caixas : []);
    },
  };
});
vi.mock('dashboard/api/autonomia/decisores', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { decisores: [] } })) },
}));
vi.mock('dashboard/composables/useCrmAutomationOptions', () => ({
  loadCrmAutomationOptions: vi.fn(() => Promise.resolve()),
  useCrmAutomationOptions: () => ({
    pipelines: { value: [] },
    stages: { value: [] },
  }),
}));
vi.mock('dashboard/api/automation', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 3, name: 'Vendas' }] } })
    ),
    getStages: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 12, name: 'Negociação' }] } })
    ),
  },
}));
// #2889: a porta (pergunta + modelos) entra só com a flag; o componente dela tem spec próprio.
vi.mock('../../porta/usePorta', async () => {
  const { ref } = await import('vue');
  porta.ligada = ref(false);
  return { usePorta: () => ({ ligada: porta.ligada, camadas: ref([]) }) };
});
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: {
    get: vi.fn(),
    passos: vi.fn(),
    ligar: vi.fn(),
    desligar: vi.fn(),
    marcarBloco: vi.fn(),
  },
}));

const CATALOGO = {
  gatilhos: [
    { tipo: 'conversa.criada', alvo: 'Conversation', frase: 'QUANDO_COMECA' },
    {
      tipo: 'card.entrou_na_etapa',
      alvo: 'Crm::Card',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_ENTROU_NA_ETAPA',
      parametros: [{ nome: 'etapa_id', peca: 'etapa' }],
    },
  ],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [{ tipo: 'parar', grupo: 'CONTROLE', frase: 'PARAR', campos: [] }],
};

const NOVA = {
  id: 3,
  nome: 'Boas-vindas',
  ativa: false,
  versao: {
    id: 21,
    receita: {
      gatilho: { tipo: 'conversa.criada' },
      passos: [{ id: 'p1', tipo: 'parar' }],
    },
  },
};
const ANTIGA = {
  id: 9,
  name: 'Etiquetar VIP',
  active: true,
  event_name: 'conversation_created',
  conditions: [],
  actions: [],
};

const montar = () =>
  mount(LivreListaPage, {
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        AutomacaoPorta: { template: '<div data-porta-stub />' },
        AutomacaoHeroi: { template: '<div data-heroi-stub />' },
      },
    },
  });

describe('LivreListaPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    AutomacoesAPI.passos.mockResolvedValue({ data: CATALOGO });
    AutomacoesAPI.get.mockResolvedValue({ data: { automacoes: [NOVA] } });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [ANTIGA] } });
    porta.ligada.value = false;
    porta.podeMudar.value = true;
    conta.passosNovos = false;
  });

  it('#2933: sem os passos novos a linha não oferece virar bloco', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-marcar-bloco]').exists()).toBe(false);
  });

  it('#2933: com os passos novos, "Usar como bloco" marca e a linha mostra o aviso', async () => {
    conta.passosNovos = true;
    AutomacoesAPI.marcarBloco.mockResolvedValue({
      data: { id: 3, bloco: true, ativa: false },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-marcar-bloco]').trigger('click');
    await flushPromises();
    expect(AutomacoesAPI.marcarBloco).toHaveBeenCalledWith(3, true);
    expect(wrapper.find('[data-bloco-aviso]').exists()).toBe(true);
  });

  it('sem a porta: título de sempre, botão Nova e vazio com convite', async () => {
    AutomacoesAPI.get.mockResolvedValue({ data: { automacoes: [] } });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-porta-stub]').exists()).toBe(false);
    expect(wrapper.find('[data-vazio]').exists()).toBe(true);
    expect(wrapper.find('[data-suas]').exists()).toBe(false);
  });

  it('com a porta e nada criado: pergunta, Montar do zero e modelos, sem o vazio de antes', async () => {
    porta.ligada.value = true;
    AutomacoesAPI.get.mockResolvedValue({ data: { automacoes: [] } });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-heroi-stub]').exists()).toBe(true);
    expect(wrapper.find('[data-porta-stub]').exists()).toBe(true);
    expect(wrapper.find('[data-vazio]').exists()).toBe(false);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
    await wrapper.find('[data-do-zero-vazio] [data-do-zero]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'automacoes_livre_nova' })
    );
  });

  it('com a porta, as automações da pessoa vêm antes dos modelos', async () => {
    porta.ligada.value = true;
    const wrapper = montar();
    await flushPromises();
    const html = wrapper.html();
    expect(html.indexOf('data-heroi-stub')).toBeLessThan(
      html.indexOf('data-linha')
    );
    expect(html.indexOf('data-linha')).toBeLessThan(
      html.indexOf('data-porta-stub')
    );
  });

  it('quem só vê fica com a lista, sem a porta', async () => {
    porta.ligada.value = true;
    porta.podeMudar.value = false;
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-heroi-stub]').exists()).toBe(false);
    expect(wrapper.find('[data-porta-stub]').exists()).toBe(false);
    expect(wrapper.findAll('[data-linha]')).toHaveLength(2);
  });

  it('com a porta e automações: "Suas automações" e Montar do zero no editor', async () => {
    porta.ligada.value = true;
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findAll('[data-linha]')).toHaveLength(2);
    expect(wrapper.find('[data-suas]').exists()).toBe(true);
    await wrapper.find('[data-do-zero]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'automacoes_livre_nova' })
    );
  });

  it('mostra as novas e as antigas, cada uma em frase', async () => {
    const wrapper = montar();
    await flushPromises();
    const linhas = wrapper.findAll('[data-linha]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('Boas-vindas');
    expect(linhas[0].find('[data-frase]').text()).toContain('QUANDO_COMECA');
    expect(linhas[0].find('[data-frase]').text()).toContain('PARAR');
    expect(linhas[1].attributes('data-antiga')).toBeDefined();
  });

  // #2499: a de card tem o selo do card e a frase com o nome da etapa; os
  // funis só são lidos quando há uma automação assim.
  it('a automação de card tem o selo do card e a etapa pelo nome', async () => {
    const montada = montar();
    await flushPromises();
    expect(CrmKanbanAPI.getPipelines).not.toHaveBeenCalled();
    expect(montada.find('[data-origem]').text()).toBe(
      'AUTOMACAO_LIVRE.ORIGEM.CONVERSA'
    );

    AutomacoesAPI.get.mockResolvedValue({
      data: {
        automacoes: [
          {
            ...NOVA,
            versao: {
              id: 22,
              receita: {
                gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
                passos: [{ id: 'p1', tipo: 'parar' }],
              },
            },
          },
        ],
      },
    });
    const wrapper = montar();
    await flushPromises();
    const linha = wrapper.find('[data-linha]');
    expect(CrmKanbanAPI.getPipelines).toHaveBeenCalledTimes(1);
    expect(linha.find('[data-origem]').text()).toBe(
      'AUTOMACAO_LIVRE.ORIGEM.CARD'
    );
    expect(linha.find('[data-frase]').text()).toContain(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA'
    );
  });

  // #2680: a frase da lista diz a caixa que abre a conversa nova, como no editor.
  it('a frase do gatilho diz a caixa da conversa nova', async () => {
    AutomacoesAPI.get.mockResolvedValue({
      data: {
        automacoes: [
          {
            ...NOVA,
            versao: {
              id: 23,
              receita: {
                gatilho: {
                  tipo: 'card.entrou_na_etapa',
                  etapa_id: 12,
                  conversa_nova: { caixa_id: 5 },
                },
                passos: [{ id: 'p1', tipo: 'parar' }],
              },
            },
          },
        ],
      },
    });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-frase]').text()).toContain(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA → WhatsApp Vendas'
    );
  });

  it('a nova mostra o fato da semana; a antiga, não (#2498)', async () => {
    AutomacoesAPI.get.mockResolvedValue({
      data: { automacoes: [{ ...NOVA, semana: { rodou: 12, parou: 1 } }] },
    });
    const wrapper = montar();
    await flushPromises();
    const linhas = wrapper.findAll('[data-linha]');
    expect(linhas[0].find('[data-fato]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.SEMANA.RODOU:12 · AUTOMACAO_LIVRE.HISTORICO.SEMANA.PAROU:1'
    );
    expect(linhas[1].find('[data-fato]').exists()).toBe(false);
  });

  it('sem rodar na semana, diz que ainda não rodou', async () => {
    AutomacoesAPI.get.mockResolvedValue({
      data: { automacoes: [{ ...NOVA, semana: { rodou: 0, parou: 0 } }] },
    });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-fato]').text()).toBe(
      'AUTOMACAO_LIVRE.HISTORICO.SEMANA.NADA'
    );
  });

  it('a antiga abre na tela de hoje; a nova, no editor', async () => {
    const wrapper = montar();
    await flushPromises();
    const linhas = wrapper.findAll('[data-linha]');
    await linhas[0].find('[data-abrir]').trigger('click');
    await linhas[1].find('[data-abrir]').trigger('click');
    expect(routerPush.mock.calls.map(([destino]) => destino.name)).toEqual([
      'automacoes_livre_editar',
      'automacoes_editar',
    ]);
  });

  it('ligar leva a versão vista e a linha continua em frase', async () => {
    AutomacoesAPI.ligar.mockResolvedValue({
      data: { ...NOVA, ativa: true, versao: { id: 21, numero: 1 } },
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-linha] [data-interruptor]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.ligar).toHaveBeenCalledWith(3, 21);
    const linha = wrapper.find('[data-linha]');
    expect(linha.text()).toContain('AUTOMACAO_LIVRE.LIGADA');
    expect(linha.find('[data-frase]').text()).toContain('PARAR');
  });

  // #2574: ligar pela lista a que manda mensagem também confirma antes.
  it('ligar a que manda mensagem confirma antes; só o "Ligar" liga', async () => {
    AutomacoesAPI.get.mockResolvedValue({
      data: {
        automacoes: [
          {
            ...NOVA,
            versao: {
              id: 21,
              receita: {
                gatilho: { tipo: 'conversa.criada' },
                passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Oi'] }],
              },
            },
          },
        ],
      },
    });
    AutomacoesAPI.ligar.mockResolvedValue({
      data: { ...NOVA, ativa: true, versao: { id: 21, numero: 1 } },
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-linha] [data-interruptor]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.ligar).not.toHaveBeenCalled();
    const confirmar = wrapper.findComponent(LivreConfirmarLigar);
    expect(confirmar.props('receita').passos[0].tipo).toBe('mensagem');

    confirmar.vm.$emit('ligar');
    await flushPromises();

    expect(AutomacoesAPI.ligar).toHaveBeenCalledWith(3, 21);
  });

  it('as automações das etapas ficam no funil: a linha leva até o quadro', async () => {
    const semCrm = montar();
    await flushPromises();
    expect(semCrm.find('[data-do-funil]').exists()).toBe(false);

    config.crmKanbanEnabled = true;
    const comCrm = montar();
    await flushPromises();
    await comCrm.find('[data-ver-funil]').trigger('click');
    expect(routerPush).toHaveBeenLastCalledWith({
      name: 'crm_kanban_index',
      params: { accountId: 1 },
    });
    config.crmKanbanEnabled = false;
  });
});
