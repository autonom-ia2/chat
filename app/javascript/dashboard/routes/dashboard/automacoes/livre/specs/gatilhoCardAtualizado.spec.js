import { mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import LivreMudanca from '../components/LivreMudanca.vue';
import { fraseDoGatilho } from '../frases';

// G27 (#2661) — o "card atualizado" no editor: o campo do card (o valor de
// venda, só para quem o vê, ou um campo personalizado), a condição e o valor.
// "Mudou" não leva valor; a frase diz o campo e a condição.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));

let podeVerValor = true;
vi.mock('../usePodeLerValor', () => ({
  usePodeLerValor: () => ({ value: () => podeVerValor }),
}));

const GATILHOS = [
  {
    tipo: 'card.atualizado',
    alvo: 'Crm::Card',
    frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_ATUALIZADO',
    grupo: 'card',
    parametros: [
      {
        nome: 'mudanca',
        peca: 'mudanca',
        obrigatorio: true,
        frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.MUDANCA',
      },
    ],
  },
];
const CATALOGO = { gatilhos: GATILHOS };
const CAMPOS = [{ value: 'documentos', label: 'Documentos' }];
const M = 'AUTOMACAO_LIVRE.MUDANCA';

const montarMudanca = (modelValue = {}) =>
  mount(LivreMudanca, {
    props: { modelValue, campos: CAMPOS },
    global: { mocks: { $t: chave => chave } },
  });
const ultimo = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];
const seletor = (wrapper, nome) =>
  wrapper
    .find(`[data-condicao="${nome}"]`)
    .findComponent({ name: 'ChoiceSelect' });

describe('gatilho "card atualizado"', () => {
  beforeEach(() => {
    podeVerValor = true;
  });

  it('ao escolher, vem em "mudou", sem campo', () => {
    const wrapper = mount(LivreGatilho, {
      props: { modelValue: null, gatilhos: GATILHOS, escolhas: {} },
      global: { mocks: { $t: chave => chave } },
    });
    wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'card.atualizado');

    expect(ultimo(wrapper)).toEqual({
      tipo: 'card.atualizado',
      mudanca: { condicao: 'mudou' },
    });
  });

  it('o campo personalizado vai pela chave; o valor de venda, sem chave', () => {
    const wrapper = montarMudanca({ condicao: 'mudou' });
    seletor(wrapper, 'campo').vm.$emit(
      'update:modelValue',
      'atributo:documentos'
    );
    expect(ultimo(wrapper)).toEqual({
      campo: 'atributo',
      chave: 'documentos',
      condicao: 'mudou',
    });

    seletor(wrapper, 'campo').vm.$emit('update:modelValue', 'valor');
    expect(ultimo(wrapper)).toEqual({ campo: 'valor', condicao: 'mudou' });
  });

  it('"mudou" não pede valor; as outras pedem, e voltar a "mudou" tira o valor', async () => {
    const wrapper = montarMudanca({ campo: 'valor', condicao: 'mudou' });
    expect(wrapper.find('[data-condicao="valor"]').exists()).toBe(false);

    await wrapper.setProps({
      modelValue: { campo: 'valor', condicao: 'passou_de', valor: '50000' },
    });
    expect(wrapper.find('[data-condicao="valor"]').exists()).toBe(true);

    seletor(wrapper, 'condicao').vm.$emit('update:modelValue', 'mudou');
    expect(ultimo(wrapper)).toEqual({ campo: 'valor', condicao: 'mudou' });
  });

  it('sem ver os valores, o valor de venda não aparece como escolha', () => {
    podeVerValor = false;
    const opcoes = seletor(montarMudanca(), 'campo').props('options');

    expect(opcoes.map(item => item.value)).toEqual(['atributo:documentos']);
  });

  it('a frase diz o campo e a condição; incompleta, a do catálogo', () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
    const gatilho = mudanca => ({ tipo: 'card.atualizado', mudanca });
    const nomes = { campoDoCard: { documentos: 'Documentos' } };

    expect(
      fraseDoGatilho(
        gatilho({ campo: 'valor', condicao: 'passou_de', valor: '50000' }),
        CATALOGO,
        t
      )
    ).toBe(`${M}.FRASE.PASSOU_DE ${M}.VALOR_DE_VENDA 50000`);
    expect(
      fraseDoGatilho(
        gatilho({ campo: 'atributo', chave: 'documentos', condicao: 'mudou' }),
        CATALOGO,
        t,
        nomes
      )
    ).toBe(`${M}.FRASE.MUDOU Documentos `);
    expect(
      fraseDoGatilho(
        gatilho({ campo: 'valor', condicao: 'igual' }),
        CATALOGO,
        t
      )
    ).toBe('AUTOMACAO_LIVRE.GATILHOS.CARD_ATUALIZADO');
  });
});
