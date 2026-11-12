import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import CardAutomacoes from '../CardAutomacoes.vue';

// #2499 F6.3 — "Automações deste card", da API do card: uma frase por automação com a espera, o passo em que está e o
// que já fez (frases do frases.js), "Parar para este card" com a confirmação numa frase, e o vazio com uma frase e um
// botão que diz o efeito real.
const { rota, push, permissao, api } = vi.hoisted(() => ({
  rota: { params: { accountId: '1' }, query: {} },
  push: vi.fn(),
  permissao: { montar: true },
  api: { doCard: vi.fn(), pararNoCard: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/api/crmAutomacoesNoCrm', () => ({ default: api }));
vi.mock('dashboard/composables/usePodeMontarAutomacao', async () => {
  const { computed } = await import('vue');
  return { usePodeMontarAutomacao: () => computed(() => permissao.montar) };
});
vi.mock('dashboard/routes/dashboard/automacoes/livre/catalogo', () => ({
  carregarCatalogo: async () => ({}),
}));
vi.mock('dashboard/routes/dashboard/automacoes/livre/frases', () => ({
  fraseDoPasso: passo => `passo ${passo.tipo}`,
}));

withFullI18n('pt_BR');

const card = { id: 5, stage_id: 12, status: 'open' };
const esperar = (id, valor) => ({
  id,
  tipo: 'esperar',
  duracao: { valor, unidade: 'dias' },
});
const LEMBRETE = {
  id: 701,
  automacao_id: 41,
  nome: 'Lembrete de proposta',
  estado: 'esperando',
  passo: 'p1',
  comecou: '2026-11-12T12:00:00.000Z',
  esperando_ate: '2026-11-15T12:00:00.000Z',
  receita: {
    gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
    passos: [esperar('p1', 3), { id: 'p2', tipo: 'avisar', texto: ['Oi'] }],
  },
  feitos: [],
};
// O passo atual dentro de um galho: o "Passo N de M" conta o passo principal que o contém.
const DE_NOVO = {
  id: 702,
  automacao_id: 42,
  nome: 'Mandar a proposta de novo',
  estado: 'esperando',
  passo: 'p2b',
  comecou: '2026-11-12T12:00:00.000Z',
  esperando_ate: '2026-11-14T12:00:00.000Z',
  receita: {
    gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
    passos: [
      { id: 'p1', tipo: 'mensagem', texto: ['Oi!'] },
      {
        id: 'p2',
        tipo: 'se',
        condicao: {},
        entao: [esperar('p2b', 2)],
        senao: [],
      },
      { id: 'p3', tipo: 'avisar', texto: ['Sumiu'] },
    ],
  },
  feitos: [{ passo: 'p1', em: '2026-11-12T12:00:05.000Z' }],
};
const SEM_PRAZO = {
  ...LEMBRETE,
  id: 703,
  automacao_id: 43,
  nome: 'Esperar a resposta',
  esperando_ate: null,
  esperando_sem_prazo: true,
};
const ANDANDO = {
  ...LEMBRETE,
  id: 704,
  automacao_id: 44,
  nome: 'Começando',
  estado: 'andando',
  passo: null,
  esperando_ate: null,
};

const responder = automacoes =>
  api.doCard.mockResolvedValue({ data: { automacoes } });

const montar = async (props = {}) => {
  const wrapper = mount(CardAutomacoes, {
    props: {
      card,
      etapa: 'Proposta enviada',
      podeGerenciar: true,
      ...props,
    },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};
const linhas = wrapper => wrapper.findAll('[data-automacao-do-card]');

describe('CardAutomacoes', () => {
  // "15 de novembro" sem o ano: o ano é o de hoje.
  beforeAll(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-12T15:00:00.000Z'));
  });
  afterAll(() => vi.useRealTimers());

  beforeEach(() => {
    rota.query = {};
    permissao.montar = true;
    push.mockClear();
    api.doCard.mockReset();
    api.pararNoCard.mockReset();
    responder([LEMBRETE, DE_NOVO]);
  });

  it('diz o que roda, até quando espera, o passo atual e o que já fez', async () => {
    const wrapper = await montar();
    expect(api.doCard).toHaveBeenCalledWith(5);
    expect(linhas(wrapper)).toHaveLength(2);
    const [lembrete, deNovo] = linhas(wrapper);
    expect(lembrete.text()).toContain(
      'Lembrete de proposta — espera até 15 de novembro'
    );
    expect(lembrete.find('[data-passo]').text()).toBe(
      'Passo 1 de 2: passo esperar'
    );
    expect(deNovo.find('[data-passo]').text()).toBe(
      'Passo 2 de 3: passo esperar'
    );
    const historico = deNovo.find('[data-historico]').text();
    expect(historico).toContain('O que já fez');
    expect(historico).toContain('12 de novembro: começou neste card');
    expect(historico).toContain('12 de novembro: passo mensagem');
  });

  it('sem prazo espera o passo; andando, age agora no primeiro passo', async () => {
    responder([SEM_PRAZO, ANDANDO]);
    const wrapper = await montar();
    const [semPrazo, andando] = linhas(wrapper);
    expect(semPrazo.text()).toContain(
      'Esperar a resposta — espera acontecer o que o passo pede'
    );
    expect(andando.text()).toContain('Começando — agindo agora');
    expect(andando.find('[data-passo]').text()).toBe(
      'Passo 1 de 2: passo esperar'
    );
  });

  it('parar pede confirmação numa frase, para só neste card e avisa que os outros continuam', async () => {
    api.pararNoCard.mockResolvedValue({ data: { paradas: 1 } });
    const wrapper = await montar();
    await linhas(wrapper)[0].find('[data-parar]').trigger('click');
    expect(wrapper.find('[data-confirma]').text()).toBe(
      'Parar Lembrete de proposta neste card? O que ela começou em outro contato, conversa ou card por causa deste também para.'
    );
    await wrapper.find('[data-parar-sim]').trigger('click');
    await flushPromises();
    expect(api.pararNoCard).toHaveBeenCalledWith(5, 41);
    expect(linhas(wrapper)).toHaveLength(1);
    expect(wrapper.find('[data-aviso-parar]').text()).toBe(
      'Lembrete de proposta parou neste card. Os outros cards continuam.'
    );
  });

  it('parar que falha fica na linha e diz para tentar de novo', async () => {
    api.pararNoCard.mockRejectedValue(new Error('rede'));
    const wrapper = await montar();
    await linhas(wrapper)[0].find('[data-parar]').trigger('click');
    await wrapper.find('[data-parar-sim]').trigger('click');
    await flushPromises();
    expect(linhas(wrapper)).toHaveLength(2);
    expect(wrapper.find('[data-aviso-parar]').text()).toBe(
      'Não deu para parar agora. Tente de novo.'
    );
  });

  it('sem a chave de mudar ou sem poder mexer no card, só vê', async () => {
    permissao.montar = false;
    const semChave = await montar();
    expect(linhas(semChave)).toHaveLength(2);
    expect(semChave.find('[data-parar]').exists()).toBe(false);

    permissao.montar = true;
    const semCard = await montar({ podeGerenciar: false });
    expect(semCard.find('[data-parar]').exists()).toBe(false);
  });

  it('card fechado não pergunta ao servidor e mostra o vazio', async () => {
    const wrapper = await montar({ card: { ...card, status: 'won' } });
    expect(api.doCard).not.toHaveBeenCalled();
    expect(wrapper.find('[data-automacoes-vazio]').exists()).toBe(true);
  });

  it('vazio: uma frase e o botão que diz o efeito real', async () => {
    responder([]);
    const wrapper = await montar();
    expect(wrapper.find('[data-automacoes-vazio] p').text()).toBe(
      'Nenhuma automação está cuidando deste card agora.'
    );
    const criar = wrapper.find('[data-criar-automacao]');
    expect(criar.text()).toBe(
      'Criar uma automação para quem entrar em Proposta enviada'
    );
    await criar.trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'automacoes_livre_nova',
      params: { accountId: '1' },
      query: { gatilho: 'card.entrou_na_etapa', etapa: '12' },
    });
  });

  it('erro de rede tem "Tentar de novo"; sem permissão, a parte some', async () => {
    api.doCard.mockRejectedValue(new Error('rede'));
    const comErro = await montar();
    expect(comErro.find('[data-automacoes-erro]').exists()).toBe(true);

    api.doCard.mockRejectedValue({ response: { status: 403 } });
    const semAcesso = await montar();
    expect(semAcesso.text()).toBe('');
  });
});
