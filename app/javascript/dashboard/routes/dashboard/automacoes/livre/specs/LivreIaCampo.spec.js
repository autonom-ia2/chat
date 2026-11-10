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

// G70 (#2880, decisão 20): o "extrair" grava também em campo do card, só onde há
// card (comCard) e nunca no campo que guarda gente (pessoa da equipe, contato).
describe('LivreIaCampo, destino no card', () => {
  const ATRIBUTOS = {
    contact_attribute: [
      { attribute_key: 'cpf', attribute_display_name: 'CPF' },
    ],
    conversation_attribute: [],
    card_attribute: [
      {
        attribute_key: 'peca',
        attribute_display_name: 'Peça',
        attribute_display_type: 'text',
      },
      {
        attribute_key: 'vendedora',
        attribute_display_name: 'Vendedora',
        attribute_display_type: 'pessoa',
      },
      {
        attribute_key: 'indicado_por',
        attribute_display_name: 'Indicado por',
        attribute_display_type: 'contato',
      },
    ],
  };

  const destinos = comCard =>
    mount(LivreIaCampo, {
      props: {
        campo: { peca: 'campos_extrair', rotulo: 'CAMPOS' },
        modelValue: [{ chave: 'peca', descricao: 'a peça', destino: '' }],
        opcoes: {},
        atributosDo: modelo => ATRIBUTOS[modelo] || [],
        comCard,
      },
      global: {
        mocks: { $t: chave => chave },
        stubs: { Button: true, ChoiceSelect: true, Switch: true },
      },
    })
      .findComponent({ name: 'ChoiceSelect' })
      .props('options')
      .map(opcao => opcao.value);

  it('com card, oferece o campo do card, sem o de gente', () => {
    const valores = destinos(true);

    expect(valores).toContain('card.atributos.peca');
    expect(valores).not.toContain('card.atributos.vendedora');
    expect(valores).not.toContain('card.atributos.indicado_por');
    expect(valores).toContain('contato.atributos.cpf');
  });

  it('sem card, não oferece campo do card', () => {
    expect(destinos(false).some(valor => valor.startsWith('card.'))).toBe(
      false
    );
  });
});

// G70: a ajuda diz qual card recebe o campo do card.
describe('LivreIaCampo, ajuda do destino no card', () => {
  const montarCampos = comCard =>
    mount(LivreIaCampo, {
      props: {
        campo: { peca: 'campos_extrair', rotulo: 'CAMPOS' },
        modelValue: [{ chave: 'peca', descricao: 'a peça', destino: '' }],
        opcoes: {},
        atributosDo: () => [],
        comCard,
      },
      global: {
        mocks: { $t: chave => chave },
        stubs: { Button: true, ChoiceSelect: true, Switch: true },
      },
    });

  it('com card, explica qual card recebe', () => {
    expect(montarCampos(true).find('[data-dica-card]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.CAMPO.DICA_CARD'
    );
  });

  it('sem card, não mostra', () => {
    expect(montarCampos(false).find('[data-dica-card]').exists()).toBe(false);
  });
});
