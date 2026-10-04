import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutomationAPI from 'dashboard/api/automation';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import DecisoresAPI from 'dashboard/api/autonomia/decisores';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import { podeMudar } from 'dashboard/composables/useCanManage';
import AutomacoesPage from '../pages/AutomacoesPage.vue';

// #859 — a lista de Automações: estados (carregando, erro, vazio com modelos,
// lista), o interruptor, o selo "criada pelo Guia" e quem só pode ver.
const { routerPush, caixas } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  caixas: { value: [] },
}));

// Com valores, a chave leva os valores junto: dá para ver o nome que a frase usa.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => (valores ? `${key} ${JSON.stringify(valores)}` : key),
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// O interruptor de permissão é um ref de verdade: o template só desembrulha ref.
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: criarRef } = await import('vue');
  const podeMudarRef = criarRef(true);
  return { useCanManage: () => podeMudarRef, podeMudar: podeMudarRef };
});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter => {
    if (getter === 'getCurrentAccountId') return ref(1);
    if (getter === 'globalConfig/get') return ref({});
    if (getter === 'inboxes/getInboxes') return ref(caixas.value);
    return ref([]);
  },
}));
vi.mock('dashboard/api/automation', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/api/autonomia/decisores', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { meta: vi.fn() },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { execucoes: vi.fn() },
}));

const regra = (id, extra = {}) => ({
  id,
  name: `Regra ${id}`,
  active: false,
  event_name: 'message_created',
  conditions: [],
  actions: [{ action_name: 'resolve_conversation', action_params: [] }],
  ...extra,
});

const montar = () =>
  mount(AutomacoesPage, {
    global: { mocks: { $t: key => key } },
  });

describe('AutomacoesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    podeMudar.value = true;
    caixas.value = [];
    window.localStorage.clear();
    AutonomiaGuideAPI.execucoes.mockResolvedValue({ data: { execucoes: [] } });
    DecisoresAPI.get.mockResolvedValue({ data: { decisores: [] } });
  });

  it('mostra o esqueleto enquanto carrega', () => {
    AutomationAPI.get.mockReturnValue(new Promise(() => {}));
    const wrapper = montar();

    expect(wrapper.find('[data-carregando]').exists()).toBe(true);
    expect(wrapper.find('[data-carregando]').attributes('aria-busy')).toBe(
      'true'
    );
  });

  it('erro diz o que fazer e tenta de novo', async () => {
    AutomationAPI.get.mockRejectedValueOnce(new Error('rede'));
    AutomationAPI.get.mockResolvedValueOnce({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-erro]').text()).toContain(
      'AUTOMACOES.LISTA.ERRO'
    );
    await wrapper.find('[data-erro] button').trigger('click');
    await flushPromises();

    expect(AutomationAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-vazio]').exists()).toBe(true);
  });

  it('vazio: uma pergunta, um botão e seis prontas que abrem a conversa', async () => {
    AutomationAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-heroi]').exists()).toBe(true);
    const modelos = wrapper.findAll('[data-modelo]');
    expect(modelos).toHaveLength(6);
    await modelos[0].trigger('click');

    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_nova',
      params: { accountId: 1 },
      query: { modelo: 'AGRADECER' },
      state: {},
    });
  });

  // O texto livre não vai na URL: um link de fora não manda pedido ao Guia.
  it('vazio: o que a pessoa escreve vai para o Guia pelo estado da navegação', async () => {
    AutomationAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-montar]').attributes('disabled')).toBeDefined();
    await wrapper.findAll('[data-ideia]')[0].trigger('click');
    await wrapper.find('[data-pedido]').setValue('  agradecer quem encerrar  ');
    await wrapper.find('form').trigger('submit');

    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_nova',
      params: { accountId: 1 },
      query: {},
      state: { pedidoAutomacao: 'agradecer quem encerrar' },
    });
  });

  it('vazio: quem só pode ver não monta', async () => {
    podeMudar.value = false;
    AutomationAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-pedido]').attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-modelo]').attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-modo-manual]').exists()).toBe(false);
  });

  it('o Guia nota a caixa com conversas sem responsável e leva o pedido pronto', async () => {
    caixas.value = [
      { id: 3, name: 'Comercial', enable_auto_assignment: false },
      { id: 4, name: 'Suporte', enable_auto_assignment: true },
    ];
    ConversationAPI.meta.mockResolvedValue({
      data: { meta: { unassigned_count: 36, all_count: 41 } },
    });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(1)] } });
    const wrapper = montar();
    await flushPromises();

    expect(ConversationAPI.meta).toHaveBeenCalledTimes(1);
    expect(ConversationAPI.meta).toHaveBeenCalledWith({
      inboxId: 3,
      status: 'open',
    });
    const sugestao = wrapper.find('[data-sugestao]');
    expect(sugestao.text()).toContain('AUTOMACOES.SUGESTAO.TEXTO');

    await sugestao.find('[data-aceitar]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'automacoes_nova',
        state: {
          pedidoAutomacao: expect.stringContaining(
            'AUTOMACOES.SUGESTAO.PEDIDO'
          ),
        },
      })
    );
  });

  it('"Agora não" esconde a sugestão daquela caixa, também na próxima visita', async () => {
    caixas.value = [
      { id: 3, name: 'Comercial', enable_auto_assignment: false },
    ];
    ConversationAPI.meta.mockResolvedValue({
      data: { meta: { unassigned_count: 9, all_count: 10 } },
    });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(1)] } });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-dispensar]').trigger('click');
    expect(wrapper.find('[data-sugestao]').exists()).toBe(false);

    const denovo = montar();
    await flushPromises();
    expect(denovo.find('[data-sugestao]').exists()).toBe(false);
  });

  it('poucas conversas sem responsável não interrompem', async () => {
    caixas.value = [
      { id: 3, name: 'Comercial', enable_auto_assignment: false },
    ];
    ConversationAPI.meta.mockResolvedValue({
      data: { meta: { unassigned_count: 2, all_count: 10 } },
    });
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(1)] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-sugestao]').exists()).toBe(false);
  });

  it('lista cada automação como Quando → Faz, com o selo do Guia só na que ele criou', async () => {
    AutomationAPI.get.mockResolvedValue({
      data: { payload: [regra(1), regra(2, { active: true })] },
    });
    AutonomiaGuideAPI.execucoes.mockResolvedValue({
      data: {
        execucoes: [
          {
            desfeita_em: null,
            passos: [
              { acao: 'POST automation_rules', ok: true, registro: 2 },
              { acao: 'POST labels', ok: true, registro: 1 },
            ],
          },
        ],
      },
    });
    const wrapper = montar();
    await flushPromises();

    const linhas = wrapper.findAll('li');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].find('[data-frase]').text()).toContain(
      'AUTOMACOES.QUANDO.MESSAGE_CREATED'
    );
    expect(wrapper.find('[data-contagem]').text()).toContain(
      'AUTOMACOES.LISTA.CONTAGEM_LIGADAS'
    );
    expect(linhas[0].find('[data-selo-guia]').exists()).toBe(true);
    expect(linhas[1].find('[data-selo-guia]').exists()).toBe(false);

    await linhas[1].find('[data-abrir]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_editar',
      params: { accountId: 1, id: 1 },
    });
  });

  it('o interruptor liga a automação e avisa', async () => {
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(5)] } });
    AutomationAPI.update.mockResolvedValue({});
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-interruptor]').trigger('click');
    await flushPromises();

    expect(AutomationAPI.update).toHaveBeenCalledWith(5, { active: true });
    expect(useAlert).toHaveBeenCalledWith('AUTOMACOES.LISTA.LIGOU');
    expect(wrapper.text()).toContain('AUTOMACOES.LISTA.LIGADA');
  });

  it('falha ao ligar não finge que ligou', async () => {
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(5)] } });
    AutomationAPI.update.mockRejectedValue(new Error('rede'));
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-interruptor]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('AUTOMACOES.LISTA.FALHA_TROCA');
    expect(wrapper.text()).toContain('AUTOMACOES.LISTA.DESLIGADA');
  });

  it('quem só pode ver não cria nem liga', async () => {
    podeMudar.value = false;
    AutomationAPI.get.mockResolvedValue({ data: { payload: [regra(5)] } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-nova]').exists()).toBe(false);
    expect(
      wrapper.find('[data-interruptor]').attributes('disabled')
    ).toBeDefined();
    await wrapper.find('[data-interruptor]').trigger('click');
    expect(AutomationAPI.update).not.toHaveBeenCalled();
  });

  // Revisão de integração (#858 x #859): o passo do Decisor aparece com o nome
  // dele, carregado da API dos Decisores.
  it('mostra o passo do Decisor com o nome dele', async () => {
    AutomationAPI.get.mockResolvedValue({
      data: {
        payload: [
          regra(7, {
            actions: [
              {
                action_name: 'perguntar_ao_decisor',
                action_params: [12, 'sim'],
              },
            ],
          }),
        ],
      },
    });
    DecisoresAPI.get.mockResolvedValue({
      data: {
        decisores: [
          {
            id: 12,
            nome: 'É lead?',
            respostas: [{ chave: 'sim', descricao: 'Pede cotação' }],
          },
        ],
      },
    });
    const wrapper = montar();
    await flushPromises();

    expect(DecisoresAPI.get).toHaveBeenCalled();
    const linha = wrapper.find('li').text();
    expect(linha).toContain('AUTOMACOES.DECISOR.PASSO');
    expect(linha).toContain('É lead?');
    expect(linha).not.toContain('AUTOMACOES.ACAO_DESCONHECIDA');
  });
});
