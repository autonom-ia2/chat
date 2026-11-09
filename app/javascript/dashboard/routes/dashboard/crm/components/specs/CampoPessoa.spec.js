import { mount } from '@vue/test-utils';
import CampoPessoa from '../CampoPessoa.vue';
import { opcoesDosValores } from 'dashboard/routes/dashboard/automacoes/livre/texto';
import {
  fraseDoValor,
  opcoesDoValor,
} from 'dashboard/routes/dashboard/automacoes/livre/frases';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

// G62 (#2829) — o campo do card do tipo pessoa da equipe.
const ChoiceFalso = {
  props: ['modelValue', 'options', 'ariaLabel'],
  emits: ['update:modelValue'],
  template:
    '<button type="button" :data-valor="modelValue" @click="$emit(\'update:modelValue\', options[1].value)" />',
};

const montar = valor =>
  mount(CampoPessoa, {
    props: {
      attribute: { attributeDisplayName: 'Responsável original', value: valor },
      pessoas: [
        { id: 3, name: 'Júlia' },
        { id: 4, name: 'Renata' },
      ],
    },
    global: { stubs: { ChoiceSelect: ChoiceFalso, Button: true } },
  });

describe('CampoPessoa', () => {
  it('mostra a pessoa guardada pelo id', () => {
    expect(montar(3).find('button').attributes('data-valor')).toBe('3');
  });

  it('escolher uma pessoa grava o id dela', async () => {
    const wrapper = montar('');
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('update')).toEqual([[4]]);
  });
});

describe('o campo de pessoa no editor da automação', () => {
  const t = (chave, params) =>
    params ? `${chave}:${JSON.stringify(params)}` : chave;
  const sim = { valor: true, frase: 'SIM' };
  const catalogo = {
    valores: [
      {
        caminho: 'card.atributos',
        atributos: 'card_attribute',
        frase: 'CARD_ATRIBUTOS',
        da_pessoa: [
          { sufixo: 'nome', frase: 'PESSOA_NOME' },
          { sufixo: 'ausente', frase: 'PESSOA_AUSENTE', opcoes: [sim] },
        ],
      },
    ],
  };
  const atributos = () => [
    {
      attribute_key: 'original',
      attribute_display_name: 'Original',
      attribute_display_type: 'pessoa',
    },
    {
      attribute_key: 'placa',
      attribute_display_name: 'Placa',
      attribute_display_type: 'text',
    },
  ];

  it('oferece o campo, o nome e a ausência só no campo de pessoa', () => {
    expect(opcoesDosValores(catalogo, atributos, t).map(o => o.value)).toEqual([
      'card.atributos.original',
      'card.atributos.original.nome',
      'card.atributos.original.ausente',
      'card.atributos.placa',
    ]);
  });

  it('a ausência tem as opções fechadas, e a frase diz o campo', () => {
    expect(opcoesDoValor('card.atributos.original.ausente', catalogo)).toEqual([
      sim,
    ]);
    expect(fraseDoValor('card.atributos.original.nome', catalogo, t)).toBe(
      'PESSOA_NOME:{"campo":"original"}'
    );
  });
});
