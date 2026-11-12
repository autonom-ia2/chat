import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import CardAutomacoes from '../CardAutomacoes.vue';

// #2414 F6.3 — "Automações deste card": uma frase por automação com a espera, o passo em que está e o que já fez
// (frases do frases.js), "Parar para este card" com a confirmação numa frase, e o vazio com uma frase e um botão
// que diz o efeito real.
const { rota, push, permissao } = vi.hoisted(() => ({
  rota: { params: { accountId: '1' }, query: {} },
  push: vi.fn(),
  permissao: { montar: true },
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
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

const card = {
  id: 5,
  stage_id: 12,
  status: 'open',
  entered_stage_at: '2026-11-12T12:00:00.000Z',
};
const montar = async (props = {}) => {
  const wrapper = mount(CardAutomacoes, {
    props: {
      card,
      marca: { etapa_id: 12 },
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
  });

  it('diz o que roda, até quando espera, o passo atual e o que já fez', async () => {
    const wrapper = await montar();
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

  it('parar pede confirmação numa frase e avisa que os outros cards continuam', async () => {
    const wrapper = await montar();
    await linhas(wrapper)[0].find('[data-parar]').trigger('click');
    expect(wrapper.find('[data-confirma]').text()).toBe(
      'Parar Lembrete de proposta só neste card?'
    );
    await wrapper.find('[data-parar-sim]').trigger('click');
    await flushPromises();
    expect(linhas(wrapper)).toHaveLength(1);
    expect(wrapper.find('[data-aviso-parar]').text()).toBe(
      'Lembrete de proposta parou neste card. Os outros cards continuam.'
    );
  });

  it('sem a chave de mudar, só vê', async () => {
    permissao.montar = false;
    const wrapper = await montar();
    expect(linhas(wrapper)).toHaveLength(2);
    expect(wrapper.find('[data-parar]').exists()).toBe(false);
  });

  it('vazio: uma frase e o botão que diz o efeito real', async () => {
    rota.query = { demo: 'vazio' };
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
});
