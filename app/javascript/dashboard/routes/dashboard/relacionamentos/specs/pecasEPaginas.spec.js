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
import { routes } from '../relacionamentos.routes';
import { routes as rotasDaPorta } from '../../relationships/routes';

// As peças comuns e a porta de Relacionamentos (#2894). Cada tela tem o spec dela em
// specs/lista, specs/ficha e specs/trazer.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));
vi.mock('../pages/ListaPage.vue', () => ({
  __esModule: true,
  default: { name: 'ListaPage', template: '<div data-pagina-nova />' },
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

  // #3057 — uma linha só em toda largura: no desktop também rola de lado e
  // mostra o degradê (com a seta) quando continua.
  it('em toda largura a fileira fica numa linha só, com rolagem e degradê', async () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'a' } });
    const classes = w.get('ul').classes();
    expect(classes).toContain('overflow-x-auto');
    expect(classes).not.toContain('md:flex-wrap');
    expect(classes).not.toContain('flex-wrap');
    await medir(w.get('ul'), { largura: 300, conteudo: 900, rolou: 300 });
    ['direita', 'esquerda'].forEach(lado =>
      expect(w.get(`[data-degrade="${lado}"]`).classes()).not.toContain(
        'md:hidden'
      )
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

// E9 (#2902): a porta de Relacionamentos abre sempre a lista nova, sem flag.
describe('porta de Relacionamentos', () => {
  const porta = rotasDaPorta.find(rota => rota.name === 'relationships_home');

  it('abre a lista nova de pessoas e empresas', async () => {
    const { default: pagina } = await porta.component();
    const w = mount(pagina);
    await flushPromises();
    expect(w.find('[data-pagina-nova]').exists()).toBe(true);
  });

  it('pede só a flag do menu de Relacionamentos', () => {
    expect(porta.meta.featureFlag).toBe(FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION);
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
    '%s pede a mesma flag da lista: relationships_navigation',
    async (_nome, rota) => {
      const next = vi.fn();
      comFlags([]);
      await rota.beforeEnter(para, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });

      const liberada = vi.fn();
      comFlags([FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION]);
      await rota.beforeEnter(para, {}, liberada);
      expect(liberada).toHaveBeenCalledWith();
    }
  );
});

// #2896 — "Trazer minha lista" é de quem pode importar contato (a mesma regra da
// importação de contatos de hoje e do servidor, ContactPolicy#import?). As fichas
// continuam com as permissões da lista.
describe('permissões das rotas de Relacionamentos', () => {
  const permissoesDe = nome =>
    routes.find(rota => rota.name === nome).meta.permissions;

  it('trazer: só administrador e a chave contact_manage', () => {
    expect(permissoesDe('relacionamentos_trazer')).toEqual([
      'administrator',
      'contact_manage',
    ]);
  });

  it.each(['relacionamentos_pessoa', 'relacionamentos_empresa'])(
    '%s continua aberta ao agente e a quem só vê contato',
    nome => {
      expect(permissoesDe(nome)).toEqual(
        expect.arrayContaining(['administrator', 'agent', 'contact_view'])
      );
    }
  );
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

// #3057 — grupo com 0 não aparece nas listas de Relacionamentos (`semVazios`):
// o primeiro ("Todos") e o escolhido ficam sempre; o escolhido com 0 fica
// apagado. Sem `semVazios`, todos aparecem.
describe('PilulasDeGrupo: grupos zerados', () => {
  const grupos = [
    { id: 'todos', nome: 'Todos', total: 0 },
    { id: 'clientes', nome: 'Clientes', total: 3 },
    { id: 'so_um', nome: 'Só tem um seguro', total: 0 },
    { id: 'sumiu', nome: 'Sumiu', total: 0 },
    { id: 'sem_numero', nome: 'Sem número' },
  ];
  const ids = w =>
    w.findAll('[data-grupo]').map(b => b.attributes('data-grupo'));

  it('com semVazios, esconde os zerados, mas "Todos" fica', () => {
    const w = mount(PilulasDeGrupo, {
      props: { grupos, modelValue: 'clientes', semVazios: true },
    });
    expect(ids(w)).toEqual(['todos', 'clientes', 'sem_numero']);
  });

  it('o grupo escolhido fica mesmo com 0, apagado', () => {
    const w = mount(PilulasDeGrupo, {
      props: { grupos, modelValue: 'sumiu', semVazios: true },
    });
    expect(ids(w)).toEqual(['todos', 'clientes', 'sumiu', 'sem_numero']);
    const sumiu = w.get('[data-grupo="sumiu"]');
    expect(sumiu.attributes('data-vazio')).toBe('');
    expect(sumiu.attributes('aria-pressed')).toBe('true');
    const todos = w.get('[data-grupo="todos"]');
    expect(todos.attributes('data-vazio')).toBe('');
    expect(todos.get('span').classes()).toContain('text-n-slate-10');
  });

  it('sem semVazios, todos aparecem', () => {
    const w = mount(PilulasDeGrupo, { props: { grupos, modelValue: 'todos' } });
    expect(ids(w)).toHaveLength(5);
  });

  it('o número fica em tom suave e a escolhida em tinta escura', () => {
    const w = mount(PilulasDeGrupo, {
      props: { grupos, modelValue: 'clientes', semVazios: true },
    });
    const escolhida = w.get('[data-grupo="clientes"] > span');
    expect(escolhida.classes()).toContain('bg-n-slate-12');
    expect(w.get('[data-grupo="todos"] > span > span').classes()).toContain(
      'text-n-slate-10'
    );
  });
});
