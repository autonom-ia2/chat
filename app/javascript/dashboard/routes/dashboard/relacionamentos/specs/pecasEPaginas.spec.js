import { flushPromises, mount } from '@vue/test-utils';
import store from 'dashboard/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { hasPermissions } from 'dashboard/helper/permissionsHelper';
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
  it('mostra a frase e as ações, todas no mesmo lugar (nenhuma solta no canto)', () => {
    const w = mount(HeroiEscuro, {
      slots: {
        frase: 'Uma frase',
        acao: '<b>Principal</b><i>Discreta</i>',
      },
    });
    expect(w.get('[data-heroi-frase]').text()).toBe('Uma frase');
    expect(w.get('[data-heroi-acao]').text()).toBe('PrincipalDiscreta');
    expect(w.find('[data-heroi-discreta]').exists()).toBe(false);
    expect(w.classes()).toContain('bg-n-heroi');
  });

  it('não desenha ação que não veio', () => {
    const w = mount(HeroiEscuro, { slots: { frase: 'Só a frase' } });
    expect(w.find('[data-heroi-acao]').exists()).toBe(false);
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

  it('tem linha visível "Carregando…" sem repetir o anúncio do leitor de tela', () => {
    const w = mount(EsqueletoDeLista);
    const visivel = w.get('p');
    expect(visivel.text()).toBe('RELACIONAMENTOS.COMUM.CARREGANDO…');
    expect(visivel.attributes('aria-hidden')).toBe('true');
    expect(visivel.classes()).toEqual(
      expect.arrayContaining(['text-sm', 'text-n-slate-11'])
    );
    expect(w.findAll('[role="status"]')).toHaveLength(1);
  });

  it('cada linha é um círculo e duas barras, com contraste e sem animar para quem pede calma', () => {
    const w = mount(EsqueletoDeLista, { props: { linhas: 2 } });
    const linhas = w.findAll('[data-esqueleto-linha]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].classes()).toContain('motion-reduce:animate-none');
    expect(linhas[0].findAll('.bg-n-slate-3')).toHaveLength(3);
    expect(linhas[0].find('.rounded-full').exists()).toBe(true);
    expect(w.find('[data-esqueleto-topo]').exists()).toBe(false);
  });

  it('com topo, desenha o bloco alto e a fileira de grupos antes das linhas', () => {
    const w = mount(EsqueletoDeLista, { props: { linhas: 3, comTopo: true } });
    expect(w.get('[data-esqueleto-topo]').classes()).toContain('bg-n-slate-3');
    expect(w.findAll('[data-esqueleto-grupos] > span')).toHaveLength(5);
    expect(w.findAll('[data-esqueleto-linha]')).toHaveLength(3);
  });
});

describe('ErroComTentarDeNovo: botão principal', () => {
  it('"Tentar de novo" é o botão principal (sólido, azul), no tamanho lg da casa', () => {
    const w = mount(ErroComTentarDeNovo);
    const botao = w.get('button');
    expect(botao.classes()).toEqual(
      expect.arrayContaining(['bg-n-blue-11', 'text-white', 'h-12'])
    );
    expect(botao.classes().join(' ')).not.toContain('bg-n-brand/10');
    expect(botao.classes().join(' ')).not.toContain('bg-n-alpha');
  });
});

describe('ErroComTentarDeNovo', () => {
  it('mostra a frase genérica e emite "tentar" no botão', async () => {
    const w = mount(ErroComTentarDeNovo);
    expect(w.attributes('role')).toBe('alert');
    expect(w.text()).toContain('RELACIONAMENTOS.COMUM.ERRO_DA_TELA');
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

  it('a partir de md a fileira quebra em linhas, sem rolagem e sem degradê', async () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    expect(w.get('ul').classes()).toEqual(
      expect.arrayContaining(['md:flex-wrap', 'md:overflow-visible'])
    );
    await medir(w.get('ul'), { largura: 300, conteudo: 900, rolou: 300 });
    ['direita', 'esquerda'].forEach(lado =>
      expect(w.get(`[data-degrade="${lado}"]`).classes()).toContain('md:hidden')
    );
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

  const comAsDuas = () =>
    comFlags([
      FEATURE_FLAGS.RELACIONAMENTOS_NOVO,
      FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION,
    ]);
  const rotaDoTrazer = routes.find(
    rota => rota.name === 'relacionamentos_trazer'
  );
  const fichas = routes.filter(rota => rota !== rotaDoTrazer);

  it.each(routes.map(rota => [rota.name, rota]))(
    '%s pede as mesmas flags da lista: relacionamentos_novo e relationships_navigation',
    async (_nome, rota) => {
      const next = vi.fn();
      comFlags([FEATURE_FLAGS.RELACIONAMENTOS_NOVO]);
      await rota.beforeEnter(para, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
    }
  );

  it.each(fichas.map(rota => [rota.name, rota]))(
    '%s abre com as duas flags',
    async (_nome, rota) => {
      const liberada = vi.fn();
      comAsDuas();
      await rota.beforeEnter(para, {}, liberada);
      expect(liberada).toHaveBeenCalledWith();
    }
  );

  // #2947 — a tela nova de trazer só lê do servidor quando a E3 (#2896) entrar.
  it('relacionamentos_trazer, com as flags e fora da demonstração, cai na importação de contatos', async () => {
    const next = vi.fn();
    comAsDuas();
    await rotaDoTrazer.beforeEnter({ ...para, query: {} }, {}, next);
    expect(next).toHaveBeenCalledWith({
      name: 'contacts_import_journey',
      params: para.params,
    });
  });

  it('relacionamentos_trazer abre na demonstração', async () => {
    const next = vi.fn();
    comAsDuas();
    const naDemo = { ...para, query: { demo: 'cheio' } };
    await rotaDoTrazer.beforeEnter(naDemo, {}, next);
    expect(next).toHaveBeenCalledWith();
    // O estado da demonstração gruda: desliga para os testes seguintes.
    await rotaDoTrazer.beforeEnter(
      { ...para, query: { demo: 'desligado' } },
      {},
      vi.fn()
    );
  });
});

// #2898 — as duas telas da renovação pedem na rota o que o servidor pede, para
// a pessoa nem chegar a uma tela que só diria "sem acesso". As chaves de cada
// assento são as que o servidor manda em `permissions`.
describe('quem chega às telas da renovação', () => {
  const ADMINISTRADOR = ['administrator'];
  const AGENTE_SEM_FUNCAO = ['agent'];
  const comFuncao = (...chaves) => ['custom_role', ...chaves];
  const chegaA = (nome, chaves) =>
    hasPermissions(
      routes.find(rota => rota.name === nome).meta.permissions,
      chaves
    );

  it.each([
    ['o administrador', ADMINISTRADOR],
    [
      'a função com a chave de mexer nos funis',
      comFuncao('crm_manage_pipelines'),
    ],
    ['a função com a chave de administrar o CRM', comFuncao('crm_admin')],
    [
      'a função que edita contatos e mexe nos funis',
      comFuncao('contact_manage', 'crm_manage_pipelines'),
    ],
  ])('%s chega a "Ajustar renovações"', (_quem, chaves) => {
    expect(chegaA('relacionamentos_renovacoes', chaves)).toBe(true);
  });

  it.each([
    ['o agente sem função', AGENTE_SEM_FUNCAO],
    ['a função que só vê contatos', comFuncao('contact_view')],
    ['a função que só edita contatos', comFuncao('contact_manage')],
    ['a função que só mexe em campos', comFuncao('attribute_manage')],
  ])('%s não chega a "Ajustar renovações"', (_quem, chaves) => {
    expect(chegaA('relacionamentos_renovacoes', chaves)).toBe(false);
  });

  it.each([
    ['o administrador', ADMINISTRADOR],
    ['o agente sem função', AGENTE_SEM_FUNCAO],
    ['a função que vê contatos', comFuncao('contact_view')],
    ['a função que edita contatos', comFuncao('contact_manage')],
  ])('%s chega a "Resultados das renovações"', (_quem, chaves) => {
    expect(chegaA('relacionamentos_resultados', chaves)).toBe(true);
  });

  it.each([
    ['a função que só mexe em campos', comFuncao('attribute_manage')],
    ['a função que só mexe nos funis', comFuncao('crm_manage_pipelines')],
  ])('%s não chega a "Resultados das renovações"', (_quem, chaves) => {
    expect(chegaA('relacionamentos_resultados', chaves)).toBe(false);
  });

  it('as fichas continuam com as permissões da lista', () => {
    const daFicha = routes.find(rota => rota.name === 'relacionamentos_pessoa');

    expect(daFicha.meta.permissions).toEqual([
      'administrator',
      'agent',
      'contact_view',
      'contact_manage',
      'attribute_manage',
    ]);
  });
});
