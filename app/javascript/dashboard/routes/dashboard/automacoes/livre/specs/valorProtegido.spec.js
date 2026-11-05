import { mount } from '@vue/test-utils';
import { comPermissoes } from '../catalogo';
import { opcoesDosValores } from '../texto';
import { podeLerComChave } from '../usePodeLerValor';
import LivreTexto from '../components/LivreTexto.vue';
import LivreCondicao from '../components/LivreCondicao.vue';

// #2597 — o valor do card pede `sales_value_view`: o editor não o oferece a
// quem não pode lê-lo, e o que já o usa continua mostrando o nome dele.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) => (valores ? `${chave} ${valores.dado}` : chave),
  }),
}));

const CATALOGO = {
  operadores: [],
  valores: [
    { caminho: 'card.titulo', base: 'card', frase: 'TITULO' },
    {
      caminho: 'card.valor',
      base: 'card',
      frase: 'VALOR',
      permissao: 'sales_value_view',
    },
  ],
};
const t = chave => chave;
const sem = comPermissoes(CATALOGO, () => false);
const com = comPermissoes(CATALOGO, chave => chave === 'sales_value_view');
const rotulos = catalogo =>
  opcoesDosValores(catalogo, () => [], t).map(item => item.label);

const STUBS = {
  TextArea: {
    props: ['modelValue'],
    template: '<textarea :value="modelValue" />',
  },
  ChoiceSelect: {
    props: ['options', 'modelValue'],
    template:
      '<div data-opcoes :data-valor="modelValue">{{ options.map(o => o.label) }}</div>',
  },
};

describe('valor que pede permissão', () => {
  it('quem pode ler segue vendo o valor do card na escolha', () => {
    expect(rotulos(com)).toEqual(['TITULO', 'VALOR']);
  });

  it('quem não pode ler não vê o valor do card na escolha; o resto fica', () => {
    expect(rotulos(sem)).toEqual(['TITULO']);
  });

  it('não muda o catálogo que veio, nem o valor sem permissão pedida', () => {
    expect(CATALOGO.valores[1].sem_permissao).toBeUndefined();
    expect(sem.valores[0]).toBe(CATALOGO.valores[0]);
  });

  it('o espelho do ve?: administrador e agente sem função leem; função só com a chave', () => {
    const ve = (papel, funcaoId, permissoes) =>
      podeLerComChave('sales_value_view', { papel, funcaoId, permissoes });

    expect(ve('administrator', 7, [])).toBe(true);
    expect(ve('agent', null, [])).toBe(true);
    expect(ve('agent', 7, ['crm_view'])).toBe(false);
    expect(ve('agent', 7, ['sales_value_view'])).toBe(true);
  });

  it('no texto que já usa o valor, ele mostra o nome, sem "apagado", e fica fora do "Pôr um dado"', () => {
    const wrapper = mount(LivreTexto, {
      props: {
        rotulo: 'TEXTO',
        modelValue: ['Valor: ', { $valor: 'card.valor' }],
        catalogo: sem,
        atributosDo: () => [],
      },
      global: { mocks: { $t: chave => chave }, stubs: STUBS },
    });

    expect(wrapper.find('textarea').element.value).toBe('Valor: [VALOR]');
    expect(wrapper.find('[data-dado-apagado]').exists()).toBe(false);
    expect(wrapper.find('[data-opcoes]').text()).not.toContain('VALOR');
  });

  it('a condição que já usa o valor continua mostrando o que olha', () => {
    const wrapper = mount(LivreCondicao, {
      props: {
        modelValue: { campo: { $valor: 'card.valor' }, op: 'maior', valor: 1 },
        catalogo: sem,
        atributosDo: () => [],
      },
      global: { mocks: { $t: chave => chave }, stubs: STUBS },
    });

    expect(wrapper.find('[data-opcoes]').text()).toContain('VALOR');
  });

  it('a condição nova não oferece o valor a quem não pode ler', () => {
    const wrapper = mount(LivreCondicao, {
      props: {
        modelValue: {
          campo: { $valor: 'card.titulo' },
          op: 'igual',
          valor: '',
        },
        catalogo: sem,
        atributosDo: () => [],
      },
      global: { mocks: { $t: chave => chave }, stubs: STUBS },
    });

    expect(wrapper.find('[data-opcoes]').text()).not.toContain('VALOR');
  });
});
