import { mount } from '@vue/test-utils';
import LivreIaCampo from '../components/LivreIaCampo.vue';

// #2500 F7 — o caminho do "decidir" mostra o nome que a pessoa escreve; a chave,
// que a IA devolve, sai dele e nunca aparece na tela.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const caminho = (nome, chave) => ({ nome, chave, descricao: 'x', passos: [] });

const montar = modelValue =>
  mount(LivreIaCampo, {
    props: {
      campo: { peca: 'caminhos', rotulo: 'CAMINHOS' },
      modelValue,
      opcoes: {},
      atributosDo: () => [],
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: { Button: true, ChoiceSelect: true, Switch: true },
    },
  });

describe('LivreIaCampo, caminhos do decidir', () => {
  it('mostra o nome, não a chave', () => {
    const wrapper = montar([
      caminho('Cotação', 'cotacao'),
      caminho('Sinistro', 'sinistro'),
    ]);

    const nomes = wrapper
      .findAll('[data-caminho]')
      .map(item => item.find('input').element.value);
    expect(nomes).toEqual(['Cotação', 'Sinistro']);
  });

  it('gera a chave do nome: minúscula, sem acento, palavras com _', async () => {
    const wrapper = montar([caminho('', ''), caminho('Sinistro', 'sinistro')]);

    await wrapper.find('[data-caminho] input').setValue('  Pós-venda  já ');

    const [lista] = wrapper.emitted('update:modelValue').at(-1);
    expect(lista[0]).toMatchObject({
      nome: '  Pós-venda  já ',
      chave: 'posvenda_ja',
    });
    expect(lista[1]).toEqual(caminho('Sinistro', 'sinistro'));
  });
});

// G41 (#2752): a instrução é opcional no "resumir". Apagada, volta null para sair
// da receita (o esquema recusa texto vazio).
describe('LivreIaCampo, instrução', () => {
  const montarInstrucao = modelValue =>
    mount(LivreIaCampo, {
      props: {
        campo: { peca: 'instrucao', rotulo: 'INSTRUCAO' },
        modelValue,
        opcoes: {},
        atributosDo: () => [],
      },
      global: { mocks: { $t: chave => chave } },
    });

  it('manda o texto escrito', async () => {
    const wrapper = montarInstrucao('');

    await wrapper.find('textarea').setValue('Inclua o que foi prometido.');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      'Inclua o que foi prometido.',
    ]);
  });

  it('apagada, manda null', async () => {
    const wrapper = montarInstrucao('Inclua o que foi prometido.');

    await wrapper.find('textarea').setValue('');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([null]);
  });
});
