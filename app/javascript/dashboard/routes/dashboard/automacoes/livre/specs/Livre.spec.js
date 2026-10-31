import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import crmPt from 'dashboard/i18n/locale/pt_BR/crm.json';
import crmEn from 'dashboard/i18n/locale/en/crm.json';
import sidebarPt from 'dashboard/i18n/locale/pt_BR/sidebarFork.json';
import LivreListaPage from '../pages/LivreListaPage.vue';
import LivreEditorPage from '../pages/LivreEditorPage.vue';
import LivreFunilPage from '../pages/LivreFunilPage.vue';
import LivreReceitasPage from '../pages/LivreReceitasPage.vue';
import LivreComecarPage from '../pages/LivreComecarPage.vue';
import LivreJornada from '../components/LivreJornada.vue';
import LivreSeletorPasso from '../components/LivreSeletorPasso.vue';
import LivreNoMeio from '../components/LivreNoMeio.vue';
import { JORNADAS } from '../prototipo/jornadas';
import { useAutomacoesLivre } from '../prototipo/useAutomacoesLivre';

// #2414 F0 — o protótipo monta sem erro em cada etapa da jornada, toda frase
// existe no i18n (pt_BR e en com as mesmas chaves) e nenhuma tela usa <select>.
const { route, push, replace } = vi.hoisted(() => ({
  route: { name: '', params: {}, query: {} },
  push: vi.fn(),
  replace: vi.fn(),
}));

vi.mock('vue-router', async () => {
  const { reactive: criar } = await import('vue');
  const rota = criar(route);
  return {
    useRoute: () => rota,
    useRouter: () => ({
      push,
      replace: destino => {
        replace(destino);
        if (destino.query) rota.query = destino.query;
      },
    }),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref } = await import('vue');
  return { useCanManage: () => ref(true) };
});

const faltando = new Set();
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: {
    pt_BR: {
      AUTOMACAO_LIVRE: crmPt.AUTOMACAO_LIVRE,
      AUTOMACOES: crmPt.AUTOMACOES,
      CRM_KANBAN: crmPt.CRM_KANBAN,
      CRM_LISTA_ACAO: crmPt.CRM_LISTA_ACAO,
      CRM_FUNIL: crmPt.CRM_FUNIL,
      FORK_SIDEBAR: sidebarPt.FORK_SIDEBAR,
      GENERAL: { CLOSE: 'Fechar' },
      SWITCH: { TOGGLE: 'Ligar ou desligar' },
    },
  },
  missing: (_locale, chave) => {
    faltando.add(chave);
  },
});
config.global.plugins = [i18n];

const PainelFalso = {
  emits: ['close'],
  methods: { open() {}, close() {}, abrir() {} },
  template: '<div><slot /><slot name="footer" /></div>',
};
const stubs = {
  SidePanel: PainelFalso,
  Dialog: {
    ...PainelFalso,
    props: ['title', 'description'],
    template: '<div data-dialog>{{ title }} {{ description }}<slot /></div>',
  },
  RouterLink: { props: ['to'], template: '<a><slot /></a>' },
  AutomacaoHeroi: true,
  CrmKanbanCard: true,
  teleport: true,
};

const loja = useAutomacoesLivre();
const ir = (name, params = {}, query = {}) => {
  route.name = name;
  route.params = { accountId: '1', ...params };
  route.query = query;
};
const montar = async componente => {
  const wrapper = mount(componente, { global: { stubs } });
  await flushPromises();
  return wrapper;
};

const folhas = (valor, prefixo = '') =>
  typeof valor === 'string'
    ? [prefixo]
    : Object.entries(valor).flatMap(([chave, filho]) =>
        folhas(filho, prefixo ? `${prefixo}.${chave}` : chave)
      );

beforeEach(() => {
  loja.reiniciar();
  faltando.clear();
});

afterEach(() => {
  expect([...faltando]).toEqual([]);
});

describe('Automação livre (protótipo F0)', () => {
  it('tem as mesmas chaves em pt_BR e en', () => {
    expect(folhas(crmEn.AUTOMACAO_LIVRE).sort()).toEqual(
      folhas(crmPt.AUTOMACAO_LIVRE).sort()
    );
  });

  it('lista cada automação com origem e linha de fato', async () => {
    ir('automacoes_livre_lista');
    const wrapper = await montar(LivreListaPage);
    expect(wrapper.findAll('[data-linha]')).toHaveLength(7);
    expect(wrapper.text()).toContain('Rodou 12 vezes esta semana · 1 parou');
    expect(wrapper.text()).toContain('Do jeito antigo');
    expect(wrapper.text()).toContain('Receita do pacote Seguros');
    expect(wrapper.html()).not.toContain('<select');
  });

  it('sem automação: uma frase e um botão', async () => {
    ir('automacoes_livre_lista', {}, { vazio: '1' });
    const wrapper = await montar(LivreListaPage);
    const vazio = wrapper.find('[data-vazio]');
    expect(vazio.findAll('p')).toHaveLength(1);
    expect(vazio.findAll('button')).toHaveLength(1);
  });

  it.each([1, 2, 3, 4, 5, 6, 7])('abre o editor da automação %i', async id => {
    ir('automacoes_livre_editar', { id: String(id) });
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.find('[data-confira]').exists()).toBe(true);
    expect(wrapper.find('[data-gatilho]').text()).not.toBe('');
    expect(wrapper.html()).not.toContain('<select');
  });

  it('renovação: galhos com um nível aberto e o selo de sem volta', async () => {
    ir('automacoes_livre_editar', { id: '1' });
    const wrapper = await montar(LivreEditorPage);
    const galhos = wrapper.findAll('[data-galho]');
    expect(galhos[0].attributes('aria-expanded')).toBe('true');
    // O Decisor dentro de "Se respondeu" fica recolhido.
    expect(wrapper.find('[data-passo="r5"]').exists()).toBe(true);
    expect(wrapper.find('[data-passo="r6"]').exists()).toBe(false);
    expect(wrapper.find('[data-sem-volta]').exists()).toBe(true);
  });

  it('"Mostrar tudo" abre todos os galhos', async () => {
    ir('automacoes_livre_editar', { id: '1' }, { tudo: '1' });
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.find('[data-passo="r6"]').exists()).toBe(true);
  });

  it.each([
    [{ receita: 'ORCAMENTO_PARADO' }, 'Retomar orçamento parado'],
    [{ receita: 'RENOVACAO' }, 'Avisar a renovação 30 dias antes'],
    [{ etapa: 'orcamento_enviado' }, 'Quando o cartão entrar em'],
    [{}, 'Escolha quando ela começa'],
  ])('editor novo com %o', async (query, texto) => {
    ir('automacoes_livre_nova', {}, query);
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.text()).toContain(texto);
  });

  it('ensaio mostra o caminho e a mensagem no celular', async () => {
    ir('automacoes_livre_editar', { id: '1' }, { aba: 'ensaiar', alvo: '201' });
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.findAll('[data-faria]').length).toBeGreaterThan(3);
    expect(wrapper.find('[data-balao]').text()).toContain('Beatriz');
    expect(wrapper.find('[data-balao]').text()).toContain('29/11/2026');
  });

  it('ensaio diz quando não começaria', async () => {
    ir('automacoes_livre_editar', { id: '2' }, { aba: 'ensaiar', alvo: '103' });
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.find('[data-nao-comeca]').text()).toContain('R$ 180,00');
  });

  it('histórico em frase e dado só leitura', async () => {
    ir('automacoes_livre_editar', { id: '2' }, { aba: 'historico' });
    let wrapper = await montar(LivreEditorPage);
    expect(wrapper.text()).toContain('Pulei: o cartão saiu da etapa antes');
    expect(wrapper.text()).toContain('Parei para não repetir em looping');
    ir('automacoes_livre_editar', { id: '3' }, { aba: 'dado' });
    wrapper = await montar(LivreEditorPage);
    expect(
      JSON.parse(wrapper.find('[data-json]').element.value).receita.passos
    ).toHaveLength(5);
  });

  it('o "+" põe o passo escolhido e cria a próxima versão', async () => {
    ir('automacoes_livre_editar', { id: '3' }, { seletor: 'raiz@1' });
    const wrapper = await montar(LivreEditorPage);
    wrapper
      .findComponent(LivreSeletorPasso)
      .vm.$emit('escolher', { tipo: 'esperar' });
    await flushPromises();
    const automacao = loja.buscar(3);
    expect(automacao.versao.numero).toBe(2);
    expect(automacao.versao.receita.passos[1].tipo).toBe('esperar');
  });

  it('com gente no meio, a mudança espera a escolha', async () => {
    ir('automacoes_livre_editar', { id: '2' }, { seletor: 'raiz@2' });
    const wrapper = await montar(LivreEditorPage);
    wrapper
      .findComponent(LivreSeletorPasso)
      .vm.$emit('escolher', { tipo: 'parar' });
    await flushPromises();
    expect(loja.buscar(2).versao.numero).toBe(2);
    expect(route.query.pessoas).toBe('1');
    expect(wrapper.findComponent(LivreNoMeio).text()).toContain(
      '8 pessoas estão no meio'
    );
    wrapper.findComponent(LivreNoMeio).vm.$emit('confirmar', 'terminam');
    await flushPromises();
    expect(loja.buscar(2).versao.numero).toBe(3);
  });

  it.each(['r3', 'r5', 'r4', 'gatilho', 'meta', 'freio', 'condicao@0'])(
    '"Alterar" abre os campos de %s',
    async alterar => {
      ir('automacoes_livre_editar', { id: '1' }, { alterar });
      const wrapper = await montar(LivreEditorPage);
      expect(wrapper.find('[data-alterar]').exists()).toBe(true);
      expect(wrapper.html()).not.toContain('<select');
    }
  );

  it('ligar com mensagem e IA pede o OK numa frase', async () => {
    ir('automacoes_livre_editar', { id: '3' }, { ligar: '1' });
    const wrapper = await montar(LivreEditorPage);
    expect(wrapper.find('[data-dialog]').text()).toContain(
      'manda mensagem ao cliente'
    );
  });

  it('seletor mostra os grupos e busca sem acento', async () => {
    const wrapper = mount(LivreSeletorPasso, { global: { stubs } });
    expect(wrapper.findAll('[data-grupo]')).toHaveLength(8);
    await wrapper.find('[data-busca] input, input').setValue('agenda');
    expect(wrapper.findAll('[data-acao]')).toHaveLength(2);
  });

  it('painel da etapa: antiga com "Trazer para o novo"', async () => {
    ir('automacoes_livre_funil', {}, { etapa: 'negociacao' });
    const wrapper = await montar(LivreFunilPage);
    expect(wrapper.find('[data-etapa-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-etapa-nova]').exists()).toBe(true);
    expect(wrapper.html()).not.toContain('<select');
  });

  it('painel do cartão: para uma execução', async () => {
    ir('automacoes_livre_funil', {}, { cartao: '101' });
    const wrapper = await montar(LivreFunilPage);
    expect(wrapper.findAll('[data-execucao]')).toHaveLength(2);
    await wrapper.find('[data-parar-cartao]').trigger('click');
    expect(wrapper.findAll('[data-execucao]')).toHaveLength(1);
  });

  it('receitas e portas montam', async () => {
    ir('automacoes_livre_receitas');
    const receitas = await montar(LivreReceitasPage);
    expect(receitas.text()).toContain('Receita do pacote Seguros');
    ir('automacoes_livre_comecar');
    const portas = await montar(LivreComecarPage);
    expect(portas.findAll('[data-porta]')).toHaveLength(3);
  });

  it('cada etapa da jornada tem nome, nota e URL própria', async () => {
    const urls = JORNADAS.flatMap(jornada =>
      jornada.etapas.map(etapa =>
        JSON.stringify([etapa.name, etapa.params, etapa.query])
      )
    );
    expect(new Set(urls).size).toBe(urls.length);
    ir('automacoes_livre_lista');
    const wrapper = await montar(LivreJornada);
    await wrapper.find('[data-abrir-jornada]').trigger('click');
    expect(wrapper.findAll('[data-etapa-jornada]')).toHaveLength(urls.length);
    JORNADAS.forEach(jornada =>
      jornada.etapas.forEach(etapa =>
        expect(
          crmPt.AUTOMACAO_LIVRE.JORNADA[jornada.chave][etapa.chave].NOTA
        ).toBeTruthy()
      )
    );
  });
});
