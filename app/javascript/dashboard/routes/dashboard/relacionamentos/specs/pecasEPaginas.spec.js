import { flushPromises, mount } from '@vue/test-utils';
import store from 'dashboard/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import HeroiEscuro from '../components/comum/HeroiEscuro.vue';
import SeloDeEstado from '../components/comum/SeloDeEstado.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import RelacionamentosInicio from '../pages/RelacionamentosInicio.vue';
import { routes } from '../relacionamentos.routes';

// As peças comuns e a porta de Relacionamentos (#2894). Cada tela tem o spec dela em
// specs/lista, specs/ficha e specs/trazer.
const flagsLigadas = vi.hoisted(() => new Set());
const carregamentos = vi.hoisted(() => ({ lista: 0 }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));
// Conta quantas vezes o módulo da tela nova foi carregado: com a flag desligada
// ele não pode nem entrar no pacote da porta.
vi.mock('../pages/ListaPage.vue', () => {
  carregamentos.lista += 1;
  return {
    __esModule: true,
    default: { name: 'ListaPage', template: '<div data-pagina-nova />' },
  };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flagsLigadas.has(flag),
  }),
}));
vi.mock('../../relationships/RelationshipsHome.vue', () => ({
  default: {
    name: 'RelationshipsHome',
    template: '<div data-pagina-antiga />',
  },
}));

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

describe('HeroiEscuro', () => {
  it('mostra a frase, a ação principal e a discreta', () => {
    const w = mount(HeroiEscuro, {
      slots: {
        frase: 'Uma frase',
        acao: '<b>Principal</b>',
        discreta: '<i>Discreta</i>',
      },
    });
    expect(w.get('[data-heroi-frase]').text()).toBe('Uma frase');
    expect(w.get('[data-heroi-acao]').text()).toBe('Principal');
    expect(w.get('[data-heroi-discreta]').text()).toBe('Discreta');
    expect(w.classes()).toContain('bg-n-heroi');
  });

  it('não desenha ação que não veio', () => {
    const w = mount(HeroiEscuro, { slots: { frase: 'Só a frase' } });
    expect(w.find('[data-heroi-acao]').exists()).toBe(false);
    expect(w.find('[data-heroi-discreta]').exists()).toBe(false);
  });
});

describe('SeloDeEstado', () => {
  it.each([
    ['cliente', 'text-n-teal-11'],
    ['alerta', 'text-n-amber-11'],
    ['neutro', 'text-n-slate-11'],
  ])('usa o visual do tom %s', (tom, classe) => {
    const w = mount(SeloDeEstado, {
      props: { tom },
      slots: { default: 'Texto' },
    });
    expect(w.attributes('data-selo')).toBe(tom);
    expect(w.classes()).toContain(classe);
    expect(w.text()).toBe('Texto');
  });
});

describe('EsqueletoDeLista', () => {
  it('desenha as linhas pedidas e avisa o leitor de tela', () => {
    const w = mount(EsqueletoDeLista, { props: { linhas: 4 } });
    expect(w.attributes('aria-busy')).toBe('true');
    expect(w.findAll('.animate-pulse')).toHaveLength(4);
    expect(w.get('.sr-only').text()).toBe('RELACIONAMENTOS.COMUM.CARREGANDO');
  });
});

describe('ErroComTentarDeNovo', () => {
  it('mostra a frase genérica e emite "tentar" no botão', async () => {
    const w = mount(ErroComTentarDeNovo);
    expect(w.attributes('role')).toBe('alert');
    expect(w.text()).toContain('RELACIONAMENTOS.COMUM.ERRO_GENERICO');
    await w.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('usa a mensagem de quem chamou', () => {
    const w = mount(ErroComTentarDeNovo, {
      props: { mensagem: 'Outra frase.' },
    });
    expect(w.text()).toContain('Outra frase.');
  });
});

describe('VazioComUmBotao', () => {
  it('mostra a frase e emite "acao" no botão', async () => {
    const w = mount(VazioComUmBotao, {
      props: { frase: 'Nada aqui.', botao: 'Fazer' },
    });
    expect(w.text()).toContain('Nada aqui.');
    await w.get('button').trigger('click');
    expect(w.emitted('acao')).toHaveLength(1);
  });
});

describe('PilulasDeGrupo: sinal de que a fila continua', () => {
  const grupos = [
    { id: 'a', nome: 'Todos', total: 280 },
    { id: 'b', nome: 'Clientes', total: 120 },
  ];
  const medir = (fila, { largura, conteudo, rolou }) => {
    Object.defineProperty(fila.element, 'clientWidth', {
      value: largura,
      configurable: true,
    });
    Object.defineProperty(fila.element, 'scrollWidth', {
      value: conteudo,
      configurable: true,
    });
    fila.element.scrollLeft = rolou;
    return fila.trigger('scroll');
  };
  const degrades = w => ({
    direita: w.find('[data-degrade="direita"]').exists(),
    esquerda: w.find('[data-degrade="esquerda"]').exists(),
  });

  it('sem transbordo, nada aparece', async () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    await medir(w.get('ul'), { largura: 500, conteudo: 500, rolou: 0 });
    expect(degrades(w)).toEqual({ direita: false, esquerda: false });
  });

  it('transbordando, o degradê aparece onde há mais conteúdo, sem pegar toque', async () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    const fila = w.get('ul');
    await medir(fila, { largura: 300, conteudo: 900, rolou: 0 });
    expect(degrades(w)).toEqual({ direita: true, esquerda: false });
    const direita = w.get('[data-degrade="direita"]');
    expect(direita.classes()).toEqual(
      expect.arrayContaining([
        'pointer-events-none',
        'bg-gradient-to-l',
        'from-n-surface-1',
      ])
    );
    expect(direita.attributes('aria-hidden')).toBe('true');
    await medir(fila, { largura: 300, conteudo: 900, rolou: 300 });
    expect(degrades(w)).toEqual({ direita: true, esquerda: true });
    await medir(fila, { largura: 300, conteudo: 900, rolou: 600 });
    expect(degrades(w)).toEqual({ direita: false, esquerda: true });
  });

  it('a pílula focada rola para longe da borda com degradê', () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    expect(w.get('ul').classes()).toContain('scroll-px-12');
  });
});

describe('PilulasDeGrupo', () => {
  const grupos = [
    { id: 'a', nome: 'Todos', total: 280 },
    { id: 'b', nome: 'Clientes', total: 0 },
    { id: 'c', nome: 'Sem número' },
  ];

  it('marca só a pílula escolhida com aria-pressed', () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'b' } });
    const apertadas = w
      .findAll('button')
      .map(b => b.attributes('aria-pressed'));
    expect(apertadas).toEqual(['false', 'true', 'false']);
  });

  it('mostra o número de cada grupo, inclusive zero, e some sem número', () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    const textos = w.findAll('button').map(b => b.text());
    expect(textos).toEqual(['Todos 280', 'Clientes 0', 'Sem número']);
  });

  it('emite o id ao clicar', async () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    await w.get('[data-grupo="b"]').trigger('click');
    expect(w.emitted('update:modelValue')).toEqual([['b']]);
  });

  it('tem alvo de 44 px e fila que rola para o lado', () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    expect(w.get('button').classes()).toContain('min-h-11');
    expect(w.get('ul').classes()).toContain('overflow-x-auto');
    expect(w.get('nav').attributes('aria-label')).toBe(
      'RELACIONAMENTOS.COMUM.GRUPOS'
    );
  });
});

describe('RelacionamentosInicio', () => {
  afterEach(() => flagsLigadas.clear());

  // Primeiro de todos: depois dele o módulo da lista já foi carregado.
  it('com a flag desligada, nem carrega o módulo da lista nova', async () => {
    const w = mount(RelacionamentosInicio);
    await flushPromises();
    expect(w.find('[data-pagina-antiga]').exists()).toBe(true);
    expect(carregamentos.lista).toBe(0);
  });

  it('abre a lista nova com relacionamentos_novo ligada', async () => {
    flagsLigadas.add(FEATURE_FLAGS.RELACIONAMENTOS_NOVO);
    const w = mount(RelacionamentosInicio);
    await flushPromises();
    expect(w.find('[data-pagina-nova]').exists()).toBe(true);
    expect(w.find('[data-pagina-antiga]').exists()).toBe(false);
  });

  it('abre a página de hoje com a flag desligada', () => {
    const w = mount(RelacionamentosInicio);
    expect(w.find('[data-pagina-antiga]').exists()).toBe(true);
    expect(w.find('[data-pagina-nova]').exists()).toBe(false);
  });
});

describe('rotas de Relacionamentos', () => {
  const para = { params: { accountId: '9' } };
  const comFlags = ligadas => {
    store.getters['accounts/getAccount'] = () => ({ id: 9 });
    store.getters['accounts/isFeatureEnabledonAccount'] = (_id, flag) =>
      ligadas.includes(flag);
  };

  it.each(routes.map(rota => [rota.name, rota]))(
    '%s pede as mesmas flags da lista: relacionamentos_novo e relationships_navigation',
    async (_nome, rota) => {
      const next = vi.fn();
      comFlags([FEATURE_FLAGS.RELACIONAMENTOS_NOVO]);
      await rota.beforeEnter(para, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });

      const liberada = vi.fn();
      comFlags([
        FEATURE_FLAGS.RELACIONAMENTOS_NOVO,
        FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION,
      ]);
      await rota.beforeEnter(para, {}, liberada);
      expect(liberada).toHaveBeenCalledWith();
    }
  );
});
