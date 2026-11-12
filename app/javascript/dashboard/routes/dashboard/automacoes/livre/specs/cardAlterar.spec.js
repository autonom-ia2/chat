import { mount } from '@vue/test-utils';
import LivreCampo from '../components/LivreCampo.vue';
import { comPermissoes, doAlvoDoGatilho } from '../catalogo';
import { modeloDaPeca } from '../useOpcoesDaConta';

// #2594 — "Mudar campos do card": só no gatilho de card, o valor de venda só
// para quem vê os valores, a data prevista pela peça de data do G16b e o valor
// digitado em reais.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const CARD_ALTERAR = {
  tipo: 'acao',
  nome: 'card_alterar',
  acao: 'PATCH crm/cards/:id',
  caminho: { id: { $valor: 'card.id' } },
  campos: [
    { nome: 'title', peca: 'texto', rotulo: 'TITULO' },
    {
      nome: 'value_cents',
      peca: 'dinheiro',
      rotulo: 'VALOR',
      permissao: 'sales_value_view',
    },
    { nome: 'custom_attributes', peca: 'atributos_do_card', rotulo: 'CAMPOS' },
  ],
};
const CATALOGO = {
  gatilhos: [
    { tipo: 'conversa.criada', alvo: 'Conversation' },
    { tipo: 'card.criado', alvo: 'Crm::Card' },
  ],
  alvos: {
    Conversation: ['conversa', 'contato'],
    'Crm::Card': ['card', 'conversa', 'contato'],
  },
  valores: [],
  passos: [CARD_ALTERAR],
};
const protegidos = dados =>
  dados.passos[0].campos
    .filter(campo => campo.sem_permissao)
    .map(campo => campo.nome);

const montar = (campo, modelValue) =>
  mount(LivreCampo, {
    props: {
      campo: { rotulo: 'ROTULO', ...campo },
      modelValue,
      catalogo: { valores: [] },
      opcoes: {},
      atributosDo: () => [],
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        LivreData: {
          props: ['modelValue'],
          template: '<div data-peca-data />',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template:
            '<button data-botao @click="$emit(\'click\')">{{ label }}</button>',
        },
        Input: {
          props: ['modelValue', 'type'],
          emits: ['update:modelValue'],
          template:
            '<input data-input :type="type" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

describe('Mudar campos do card', () => {
  it('só aparece no gatilho de card', () => {
    expect(doAlvoDoGatilho(CATALOGO, 'conversa.criada').passos).toEqual([]);
    expect(
      doAlvoDoGatilho(CATALOGO, 'card.criado').passos.map(item => item.nome)
    ).toEqual(['card_alterar']);
  });

  it('marca o valor de venda para quem não vê os valores e mantém o resto', () => {
    const semVer = comPermissoes(CATALOGO, () => false);

    expect(semVer.passos[0].campos).toHaveLength(3);
    expect(protegidos(semVer)).toEqual(['value_cents']);
    expect(
      protegidos(comPermissoes(CATALOGO, chave => chave === 'sales_value_view'))
    ).toEqual([]);
    expect(CATALOGO.passos[0].campos[1].sem_permissao).toBeUndefined();
  });

  // Revisão do #2594: o valor que outra pessoa pôs fica travado, sem o valor,
  // e "Tirar" o tira do passo; sem isso o salvar recusaria sem saída.
  it('o valor de venda que já está no passo aparece travado, com Tirar', async () => {
    const campo = {
      nome: 'value_cents',
      peca: 'dinheiro',
      permissao: 'sales_value_view',
      sem_permissao: true,
    };
    const wrapper = montar(campo, 150000);

    expect(wrapper.find('[data-campo-protegido]').exists()).toBe(true);
    expect(wrapper.find('[data-input]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('1500');

    await wrapper.find('[data-tirar-protegido]').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([[null]]);
  });

  it('os campos personalizados são os do card', () => {
    expect(modeloDaPeca('atributos_do_card')).toBe('card_attribute');
  });

  it('o valor aparece em reais e grava em centavos; vazio sai do corpo', async () => {
    const wrapper = montar({ nome: 'value_cents', peca: 'dinheiro' }, 150000);
    const caixa = wrapper.find('[data-input]');

    expect(caixa.attributes('type')).toBe('number');
    expect(caixa.element.value).toBe('1500');

    await caixa.setValue('1234.56');
    await caixa.setValue('');

    expect(wrapper.emitted('update:modelValue')).toEqual([[123456], [null]]);
  });

  it('a data prevista usa a peça de data, também com a data calculada', () => {
    const dia = montar({ nome: 'expected_close_at', peca: 'data' }, null);
    const calculada = montar(
      { nome: 'expected_close_at', peca: 'data' },
      { $data: { de: 'hoje', mais: { valor: 6, unidade: 'meses' } } }
    );

    expect(dia.find('[data-peca-data]').exists()).toBe(true);
    expect(calculada.find('[data-peca-data]').exists()).toBe(true);
    expect(calculada.find('[data-calculado]').exists()).toBe(false);
  });
});
