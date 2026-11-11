import { mount } from '@vue/test-utils';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import HeroiEscuro from '../components/comum/HeroiEscuro.vue';
import SeloDeEstado from '../components/comum/SeloDeEstado.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import ListaPage from '../pages/ListaPage.vue';
import FichaDaPessoaPage from '../pages/FichaDaPessoaPage.vue';
import FichaDaEmpresaPage from '../pages/FichaDaEmpresaPage.vue';
import TrazerListaPage from '../pages/TrazerListaPage.vue';
import RelacionamentosInicio from '../pages/RelacionamentosInicio.vue';

// As peças comuns e as cascas das telas de Relacionamentos (#2894).
const flagsLigadas = vi.hoisted(() => new Set());

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {} }) }));
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

describe('cascas das telas', () => {
  it.each([
    [ListaPage, 'lista', 'RELACIONAMENTOS.LISTA.TITULO'],
    [FichaDaPessoaPage, 'pessoa', 'RELACIONAMENTOS_FICHA.PESSOA.TITULO'],
    [FichaDaEmpresaPage, 'empresa', 'RELACIONAMENTOS_FICHA.EMPRESA.TITULO'],
    [TrazerListaPage, 'trazer', 'RELACIONAMENTOS_TRAZER.TITULO'],
  ])('mostra o título e a marca da tela %#', (Pagina, nome, chave) => {
    const w = mount(Pagina);
    expect(w.attributes('data-relacionamentos')).toBe(nome);
    expect(w.get('h1').text()).toBe(chave);
  });
});

describe('RelacionamentosInicio', () => {
  afterEach(() => flagsLigadas.clear());

  it('abre a lista nova com relacionamentos_novo ligada', () => {
    flagsLigadas.add(FEATURE_FLAGS.RELACIONAMENTOS_NOVO);
    const w = mount(RelacionamentosInicio);
    expect(w.find('[data-relacionamentos="lista"]').exists()).toBe(true);
    expect(w.find('[data-pagina-antiga]').exists()).toBe(false);
  });

  it('abre a página de hoje com a flag desligada', () => {
    const w = mount(RelacionamentosInicio);
    expect(w.find('[data-pagina-antiga]').exists()).toBe(true);
    expect(w.find('[data-relacionamentos="lista"]').exists()).toBe(false);
  });
});
