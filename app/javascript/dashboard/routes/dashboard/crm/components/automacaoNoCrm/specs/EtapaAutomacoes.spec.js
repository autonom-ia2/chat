import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import EtapaAutomacoes from '../EtapaAutomacoes.vue';

// #2499 F6.5 — as regras antigas (do store) e as automações novas (da API da etapa) numa lista só, na mesma linha da
// lista de Automações (frase, "Alterar" e interruptor); a frase das novas sai do frases.js; ligar a nova é o "assumir e
// religar" da automação, com a confirmação da lista quando ela manda mensagem; o aviso da F6.4 só com automação de
// entrar ou sair; o vazio com uma frase e um botão; sair com o funil mudado pergunta antes.
const { rota, push, permissao, despachar, api, automacoes, confirmar } =
  vi.hoisted(() => ({
    rota: { params: { accountId: '1' }, query: {} },
    push: vi.fn(),
    permissao: { montar: true },
    despachar: vi.fn(),
    api: { daEtapa: vi.fn() },
    automacoes: {
      ligar: vi.fn(),
      desligar: vi.fn(),
      custosDaAutomacao: vi.fn(),
    },
    confirmar: { abrir: vi.fn() },
  }));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ dispatch: despachar }),
}));
vi.mock('dashboard/api/crmAutomacoesNoCrm', () => ({ default: api }));
vi.mock('dashboard/api/autonomia/automacoes', () => ({ default: automacoes }));
vi.mock('dashboard/composables/usePodeMontarAutomacao', async () => {
  const { computed } = await import('vue');
  return { usePodeMontarAutomacao: () => computed(() => permissao.montar) };
});
vi.mock('dashboard/routes/dashboard/automacoes/livre/catalogo', () => ({
  carregarCatalogo: async () => ({}),
}));
vi.mock('dashboard/routes/dashboard/automacoes/livre/frases', () => ({
  fraseDoGatilho: (gatilho, _catalogo, _t, nomes) =>
    `gatilho ${gatilho.tipo} em ${nomes.etapa[gatilho.etapa_id]}`,
  fraseDoPasso: passo => `passo ${passo.tipo}`,
}));
// A confirmação de verdade é um diálogo da casa: aqui basta saber que abriu e poder dizer "Ligar".
vi.mock(
  'dashboard/routes/dashboard/automacoes/livre/components/LivreConfirmarLigar.vue',
  () => ({
    default: defineComponent({
      name: 'LivreConfirmarLigar',
      setup(_props, { expose }) {
        expose({ abrir: confirmar.abrir });
        return () => h('div', { 'data-confirmar-ligar': '' });
      },
    }),
  })
);

withFullI18n('pt_BR');

const REGRA = {
  id: 9,
  name: 'Ligar no dia seguinte',
  trigger_event: 'on_enter',
  enabled: true,
  steps: [
    { action_type: 'create_follow_up', action_config: { title: 'Ligar' } },
  ],
};
const entrou = { tipo: 'card.entrou_na_etapa', etapa_id: 12 };
const NOVAS = [
  {
    id: 41,
    nome: 'Lembrete de proposta',
    ativa: true,
    versao: {
      id: 401,
      receita: {
        gatilho: entrou,
        passos: [
          { id: 'p1', tipo: 'esperar', duracao: { valor: 3, unidade: 'dias' } },
        ],
      },
    },
  },
  {
    id: 43,
    nome: 'Mandar a proposta de novo',
    ativa: false,
    versao: {
      id: 403,
      receita: {
        gatilho: entrou,
        passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Oi!'] }],
      },
    },
  },
  {
    id: 44,
    nome: 'Esperar o fim do dia',
    ativa: false,
    versao: {
      id: 404,
      receita: {
        gatilho: { tipo: 'card.parado', etapa_id: 12, dias: 5 },
        passos: [
          { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
        ],
      },
    },
  },
];
let antigas = [];
let novas = [];
const responder = erro => {
  despachar.mockImplementation(async (acao, dados) => {
    if (acao === 'crmKanban/fetchStageAutomations') {
      if (erro) throw erro;
      return antigas;
    }
    return { ...REGRA, enabled: dados.automation.enabled };
  });
  api.daEtapa.mockImplementation(async () => ({
    data: { automacoes: novas },
  }));
};

const montar = async (props = {}) => {
  const wrapper = mount(EtapaAutomacoes, {
    props: { etapaId: 12, etapaNome: 'Proposta enviada', ...props },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};
const linhas = wrapper => wrapper.findAll('[data-automacao-da-etapa]');
const alternarLinha = async (wrapper, indice) => {
  await linhas(wrapper)
    [indice].findComponent({ name: 'Switch' })
    .vm.$emit('update:modelValue', true);
  await flushPromises();
};

describe('EtapaAutomacoes', () => {
  beforeEach(() => {
    rota.query = {};
    permissao.montar = true;
    push.mockClear();
    despachar.mockReset();
    Object.values(api).forEach(fn => fn.mockReset());
    Object.values(automacoes).forEach(fn => fn.mockReset());
    confirmar.abrir.mockReset();
    antigas = [REGRA];
    novas = NOVAS;
    responder();
  });

  it('mostra a regra antiga do store e as novas da API da etapa na linha da lista de Automações', async () => {
    const wrapper = await montar();
    expect(despachar).toHaveBeenCalledWith(
      'crmKanban/fetchStageAutomations',
      12
    );
    expect(api.daEtapa).toHaveBeenCalledWith(12);
    expect(linhas(wrapper)).toHaveLength(4);
    const [antiga, nova] = linhas(wrapper);
    expect(antiga.find('[data-jeito-antigo]').text()).toBe('Jeito antigo');
    expect(antiga.find('[data-frase]').text()).toContain(
      'Quando o card entra nesta etapa'
    );
    expect(antiga.find('[data-frase]').text()).toContain(
      'Criar o retorno “Ligar”'
    );
    expect(nova.find('[data-jeito-antigo]').exists()).toBe(false);
    expect(nova.find('[data-frase]').text()).toContain(
      'gatilho card.entrou_na_etapa em Proposta enviada'
    );
    expect(nova.find('[data-frase]').text()).toContain('passo esperar');
    expect(wrapper.findAll('[data-interruptor]')).toHaveLength(4);
  });

  it('o interruptor da regra antiga salva no store', async () => {
    const wrapper = await montar();
    await linhas(wrapper)[0]
      .findComponent({ name: 'Switch' })
      .vm.$emit('update:modelValue', false);
    await flushPromises();
    expect(despachar).toHaveBeenCalledWith('crmKanban/saveStageAutomation', {
      stageId: 12,
      automation: { id: 9, enabled: false },
    });
    expect(linhas(wrapper)[0].text()).toContain('Desligada');
  });

  it('desligar a nova chama o desligar da automação', async () => {
    automacoes.desligar.mockResolvedValue({ data: { id: 41, ativa: false } });
    const wrapper = await montar();
    await linhas(wrapper)[1]
      .findComponent({ name: 'Switch' })
      .vm.$emit('update:modelValue', false);
    await flushPromises();
    expect(automacoes.desligar).toHaveBeenCalledWith(41);
    expect(linhas(wrapper)[1].text()).toContain('Desligada');
  });

  it('ligar a nova sem mensagem liga direto, na versão que a tela mostrou', async () => {
    automacoes.ligar.mockResolvedValue({ data: { id: 44, ativa: true } });
    const wrapper = await montar();
    await alternarLinha(wrapper, 3);
    expect(confirmar.abrir).not.toHaveBeenCalled();
    expect(automacoes.ligar).toHaveBeenCalledWith(44, 404);
    expect(linhas(wrapper)[3].text()).toContain('Ligada');
  });

  it('ligar a nova que manda mensagem pede a confirmação da lista antes', async () => {
    automacoes.custosDaAutomacao.mockResolvedValue({
      data: { com_valores: false },
    });
    automacoes.ligar.mockResolvedValue({ data: { id: 43, ativa: true } });
    const wrapper = await montar();
    await alternarLinha(wrapper, 2);
    expect(confirmar.abrir).toHaveBeenCalledTimes(1);
    expect(automacoes.ligar).not.toHaveBeenCalled();

    wrapper.findComponent({ name: 'LivreConfirmarLigar' }).vm.$emit('ligar');
    await flushPromises();
    expect(automacoes.ligar).toHaveBeenCalledWith(43, 403);
  });

  it('ligar recusado mostra o porquê que o servidor deu', async () => {
    automacoes.ligar.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Quem liga não alcança a etapa.', problemas: [] },
      },
    });
    const wrapper = await montar();
    await alternarLinha(wrapper, 3);
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Quem liga não alcança a etapa.'
    );
    expect(linhas(wrapper)[3].text()).toContain('Desligada');
  });

  it('"Alterar" da antiga abre as ações da etapa; o da nova, o editor dela', async () => {
    const wrapper = await montar();
    await linhas(wrapper)[0].find('[data-alterar]').trigger('click');
    expect(wrapper.emitted('antigas')).toHaveLength(1);
    await linhas(wrapper)[1].find('[data-alterar]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_livre_editar',
      params: { accountId: '1', id: '41' },
    });
  });

  it('"Nova automação para esta etapa" abre o editor com o gatilho da etapa', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-nova-automacao]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_livre_nova',
      params: { accountId: '1' },
      query: { gatilho: 'card.entrou_na_etapa', etapa: '12' },
    });
  });

  it('com o funil mudado, pergunta antes de sair', async () => {
    const wrapper = await montar({ temMudanca: true });
    await wrapper.find('[data-nova-automacao]').trigger('click');
    expect(push).not.toHaveBeenCalled();
    expect(wrapper.find('[data-sair-sem-salvar]').text()).toContain(
      'Sair sem salvar? O que você mudou no funil não fica guardado.'
    );
    await wrapper.find('[data-sair-ficar]').trigger('click');
    expect(wrapper.find('[data-sair-sem-salvar]').exists()).toBe(false);
    expect(push).not.toHaveBeenCalled();

    await wrapper.find('[data-nova-automacao]').trigger('click');
    await wrapper.find('[data-sair-sim]').trigger('click');
    expect(push).toHaveBeenCalledTimes(1);
  });

  it('o aviso da F6.4 cobre os três caminhos e só aparece com automação de entrar ou sair', async () => {
    const wrapper = await montar();
    const aviso = wrapper.find('[data-aviso-nao-dispara]').text();
    expect(aviso).toContain('arquivar vários cards de uma vez');
    expect(aviso).toContain('apagar a etapa');
    expect(aviso).toContain('mover cards pela integração');

    antigas = [];
    novas = [NOVAS[2]];
    const soParado = await montar();
    expect(soParado.find('[data-aviso-nao-dispara]').exists()).toBe(false);
  });

  it('vazio: uma frase e um botão, sem ajuda nem aviso', async () => {
    antigas = [];
    novas = [];
    const wrapper = await montar({ etapaId: 13 });
    expect(wrapper.find('[data-etapa-automacoes-vazio]').text()).toBe(
      'Esta etapa ainda não tem automação.'
    );
    expect(wrapper.find('[data-nova-automacao]').exists()).toBe(true);
    expect(wrapper.find('[data-aviso-nao-dispara]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('O que acontece sozinho');
  });

  it('sem a chave de mudar, vê a lista sem botão e com o interruptor travado', async () => {
    permissao.montar = false;
    const wrapper = await montar();
    expect(wrapper.find('[data-nova-automacao]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Você pode ver.');
    const travados = wrapper
      .findAll('[data-interruptor]')
      .filter(item => item.attributes('disabled') !== undefined);
    expect(travados).toHaveLength(4);
  });

  it('erro de rede tem "Tentar de novo"; sem permissão, a parte some', async () => {
    responder(new Error('rede'));
    const comErro = await montar();
    expect(comErro.find('[data-etapa-automacoes-erro]').exists()).toBe(true);

    responder();
    api.daEtapa.mockRejectedValue({ response: { status: 403 } });
    const semAcesso = await montar();
    expect(semAcesso.find('[data-etapa-automacoes]').exists()).toBe(false);
  });
});
