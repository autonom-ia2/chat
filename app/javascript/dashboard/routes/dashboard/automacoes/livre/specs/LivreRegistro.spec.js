import { mount } from '@vue/test-utils';
import LivreRegistro from '../components/LivreRegistro.vue';

// G18 (#2671) — a peça "onde fazer os passos de dentro": o contato guardado num
// campo do card do tipo contato (decisão 16), ou os outros cards do contato (só para quem mexe no
// funil). Cada troca sai inteira, só com o que a ligação usa.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));

const ChoiceFalso = {
  name: 'ChoiceSelect',
  props: ['modelValue', 'options', 'ariaLabel', 'placeholder'],
  emits: ['update:modelValue'],
  template: '<div />',
};

const CATALOGO = {
  alvo: 'Crm::Card',
  alvos: { 'Crm::Card': ['card', 'conversa', 'contato', 'reuniao'] },
  valores: [
    { caminho: 'card.atributos', frase: 'CAMPO_DO_CARD', atributos: true },
  ],
};
const ATRIBUTOS = {
  card_attribute: [
    { attribute_key: 'indicado_por', attribute_display_type: 'contato' },
    // Campo de número não aponta contato (decisão 16): o servidor recusa.
    { attribute_key: 'numero_do_cliente', attribute_display_type: 'number' },
    { attribute_key: 'placa', attribute_display_type: 'text' },
  ],
  contact_attribute: [
    { attribute_key: 'quem_indicou', attribute_display_type: 'number' },
  ],
  conversation_attribute: [
    { attribute_key: 'numero_do_pedido', attribute_display_type: 'number' },
  ],
};

const montar = (props = {}) =>
  mount(LivreRegistro, {
    props: {
      rotulo: 'ONDE',
      modelValue: {},
      catalogo: CATALOGO,
      atributosDo: modelo => ATRIBUTOS[modelo] || [],
      escolhas: {
        funis: [{ value: 3, label: 'Vendas' }],
        etapas: [
          { label: 'Vendas', options: [{ value: 9, label: 'Proposta' }] },
        ],
      },
      ...props,
    },
    global: { stubs: { ChoiceSelect: ChoiceFalso } },
  });

const escolha = (wrapper, seletor) =>
  wrapper.find(seletor).findComponent(ChoiceFalso);
const valores = opcoes => opcoes.map(opcao => opcao.value);

describe('LivreRegistro', () => {
  it('sem a chave de funis, só oferece o contato do campo', () => {
    expect(
      valores(escolha(montar(), '[data-ligacao]').props('options'))
    ).toEqual(['contato_do_campo']);
    expect(
      valores(
        escolha(montar({ podeLerCards: true }), '[data-ligacao]').props(
          'options'
        )
      )
    ).toEqual(['contato_do_campo', 'cards_do_contato']);
  });

  it('escolher o contato do campo começa na conversa dele', () => {
    const wrapper = montar();
    escolha(wrapper, '[data-ligacao]').vm.$emit(
      'update:modelValue',
      'contato_do_campo'
    );

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { de: 'contato_do_campo', usar: 'conversa' },
    ]);
  });

  it('o campo oferece só os campos do card do tipo contato', () => {
    const wrapper = montar({
      modelValue: { de: 'contato_do_campo', usar: 'conversa' },
    });
    const campos = escolha(wrapper, '[data-campo]').props('options');

    expect(valores(campos)).toEqual(['card.atributos.indicado_por']);
    escolha(wrapper, '[data-campo]').vm.$emit(
      'update:modelValue',
      'card.atributos.indicado_por'
    );
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      {
        de: 'contato_do_campo',
        usar: 'conversa',
        campo: { $valor: 'card.atributos.indicado_por' },
      },
    ]);
  });

  // Decisão 19: no gatilho de conversa, a âncora lê o card dela (só para
  // ler), e só com a chave de funis.
  it('no gatilho de conversa, o campo do card só para quem tem a chave de funis', () => {
    const daConversa = {
      ...CATALOGO,
      alvo: 'Conversation',
      alvos: { Conversation: ['conversa', 'contato', 'card'] },
    };
    const comChave = montar({
      catalogo: daConversa,
      podeLerCards: true,
      modelValue: { de: 'contato_do_campo', usar: 'conversa' },
    });
    const semChave = montar({
      catalogo: daConversa,
      modelValue: { de: 'contato_do_campo', usar: 'conversa' },
    });

    expect(valores(escolha(comChave, '[data-campo]').props('options'))).toEqual(
      ['card.atributos.indicado_por']
    );
    expect(semChave.find('[data-campo]').exists()).toBe(false);
  });

  it('sem campo do tipo contato, diz o que fazer em vez de uma lista vazia', () => {
    const wrapper = montar({
      modelValue: { de: 'contato_do_campo' },
      // Só campos de número: nenhum serve para apontar o contato.
      atributosDo: () => [
        { attribute_key: 'indicado_por', attribute_display_type: 'number' },
      ],
    });

    expect(wrapper.find('[data-sem-campo]').exists()).toBe(true);
    expect(wrapper.find('[data-aviso-do-campo]').exists()).toBe(true);
    expect(wrapper.find('[data-campo]').exists()).toBe(false);
  });

  it('nos cards, trocar o funil tira a etapa e "qualquer funil" sai do registro', () => {
    const wrapper = montar({
      podeLerCards: true,
      modelValue: {
        de: 'cards_do_contato',
        funil_id: 3,
        etapa_id: 9,
        situacao: ['lost'],
      },
    });

    expect(valores(escolha(wrapper, '[data-etapa]').props('options'))).toEqual([
      null,
      9,
    ]);
    escolha(wrapper, '[data-funil]').vm.$emit('update:modelValue', null);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { de: 'cards_do_contato', situacao: ['lost'] },
    ]);
  });

  it('"só o mais recente" entra e sai do registro', () => {
    const wrapper = montar({
      podeLerCards: true,
      modelValue: { de: 'cards_do_contato' },
    });

    escolha(wrapper, '[data-mais-recente]').vm.$emit('update:modelValue', true);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { de: 'cards_do_contato', mais_recente: true },
    ]);
    escolha(wrapper, '[data-mais-recente]').vm.$emit(
      'update:modelValue',
      false
    );
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { de: 'cards_do_contato' },
    ]);
  });
});
