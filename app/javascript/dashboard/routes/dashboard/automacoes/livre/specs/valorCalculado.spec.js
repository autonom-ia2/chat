import { mount } from '@vue/test-utils';
import LivreCampo from '../components/LivreCampo.vue';
import { campoDasPartes, partesDoCampo } from '../texto';
import { linhasDoEnsaio } from '../ensaio';
import { fraseDoCalculado } from '../frases';

// #2414 G16 — valor calculado no corpo da ação. O campo de texto aceita dado
// da conversa e grava `{ $texto }`; a data que o Guia montou aparece em frase;
// o ensaio mostra o que gravaria agora ou por que pularia.
const t = (chave, valores, n) =>
  `${chave}${valores && Object.keys(valores).length ? `(${Object.values(valores).join(',')})` : ''}${n === undefined ? '' : `#${n}`}`;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const CATALOGO = {
  valores: [
    { caminho: 'contato.nome', frase: 'NOME' },
    { caminho: 'card.atributos', atributos: 'card_attribute', frase: 'ATRIB' },
  ],
};

const montar = (campo, modelValue, atributos = []) =>
  mount(LivreCampo, {
    props: {
      campo: { nome: campo.nome, rotulo: 'ROTULO', ...campo },
      modelValue,
      catalogo: CATALOGO,
      opcoes: {},
      atributos,
      atributosDo: () => [],
    },
    global: {
      mocks: { $t: t },
      stubs: {
        TextArea: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<textarea :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
        Input: { props: ['modelValue'], template: '<input data-input />' },
        ChoiceSelect: { template: '<div data-escolha />' },
      },
    },
  });

describe('partesDoCampo e campoDasPartes', () => {
  it('só texto fica string; com dado vira $texto; vazio sai do corpo', () => {
    expect(campoDasPartes(['Oi'])).toBe('Oi');
    expect(campoDasPartes(['Oi ', { $valor: 'contato.nome' }])).toEqual({
      $texto: ['Oi ', { $valor: 'contato.nome' }],
    });
    expect(campoDasPartes([])).toBe('');
  });

  it('lê string, $texto e o $valor sozinho que o Guia montou', () => {
    expect(partesDoCampo('Oi')).toEqual(['Oi']);
    expect(partesDoCampo({ $texto: ['a', { $valor: 'x' }] })).toEqual([
      'a',
      { $valor: 'x' },
    ]);
    expect(partesDoCampo({ $valor: 'x' })).toEqual([{ $valor: 'x' }]);
    expect(partesDoCampo(undefined)).toEqual([]);
  });
});

describe('LivreCampo com valor calculado', () => {
  it('o campo de texto mostra o dado entre colchetes e grava $texto', async () => {
    const wrapper = montar(
      { nome: 'name', peca: 'texto' },
      { $texto: ['indicado por ', { $valor: 'contato.nome' }] }
    );
    const caixa = wrapper.find('textarea');
    expect(caixa.element.value).toBe('indicado por [NOME]');

    await caixa.setValue('Oi [NOME]');
    await caixa.setValue('Oi');

    expect(wrapper.emitted('update:modelValue')).toEqual([
      [{ $texto: ['Oi ', { $valor: 'contato.nome' }] }],
      ['Oi'],
    ]);
  });

  it('a data calculada pelo Guia aparece em frase e não vira caixa de texto', () => {
    const wrapper = montar(
      { nome: 'name', peca: 'texto' },
      { $data: { de: 'hoje', mais: { valor: 6, unidade: 'meses' } } }
    );

    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.find('[data-calculado]').text()).toContain(
      'DATA_MAIS(AUTOMACAO_LIVRE.ALTERAR_PAINEL.HOJE,6,'
    );
  });

  it('o atributo de texto aceita dado; o de data abre a peça de data', async () => {
    const atributos = [
      {
        attribute_key: 'nota',
        attribute_display_name: 'Nota',
        attribute_display_type: 'text',
      },
      {
        attribute_key: 'revisao',
        attribute_display_name: 'Revisão',
        attribute_display_type: 'date',
      },
    ];
    const wrapper = montar(
      { nome: 'custom_attributes', peca: 'atributos_do_card' },
      { revisao: { $data: { de: 'hoje' } }, nota: 'x' },
      atributos
    );

    expect(wrapper.find('[data-peca="data"]').text()).toContain('Revisão');
    await wrapper.find('textarea').setValue('por [NOME]');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      {
        revisao: { $data: { de: 'hoje' } },
        nota: { $texto: ['por ', { $valor: 'contato.nome' }] },
      },
    ]);
  });
});

describe('fraseDoCalculado', () => {
  it('diz de onde vem e quanto soma, com o plural da unidade', () => {
    expect(
      fraseDoCalculado(
        { $data: { de: 'hoje', mais: { valor: -1, unidade: 'meses' } } },
        CATALOGO,
        t
      )
    ).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA_CALCULADA(AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA_MENOS(AUTOMACAO_LIVRE.ALTERAR_PAINEL.HOJE,1,AUTOMACAO_LIVRE.UNIDADES.MESES#1))'
    );
    expect(fraseDoCalculado({ $valor: 'contato.nome' }, CATALOGO, t)).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.DA_CONVERSA(NOME)'
    );
    expect(
      fraseDoCalculado(
        { $texto: ['oi ', { $valor: 'contato.nome' }] },
        CATALOGO,
        t
      )
    ).toBe('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CALCULADO_TEXTO(oi [NOME])');
    expect(
      fraseDoCalculado(
        { $data: { de: { $valor: 'contato.nome' } } },
        CATALOGO,
        t
      )
    ).toBe('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA_CALCULADA(NOME)');
  });
});

describe('linhasDoEnsaio com a ação calculada', () => {
  const fraseDe = id => `frase ${id}`;

  it('mostra o que gravaria agora, com a data no formato da tela', () => {
    const [linha] = linhasDoEnsaio(
      [
        {
          id: 'p1',
          tipo: 'acao',
          faria: 'acao',
          dados: { calculados: [{ campo: 'revisao', valor: '2027-05-04' }] },
        },
      ],
      fraseDe,
      t
    );
    const dia = new Date(2027, 4, 4, 12).toLocaleDateString();

    expect(linha.destaque).toBe(
      `AUTOMACAO_LIVRE.ENSAIO.FARIA.GRAVARIA(revisao: ${dia})`
    );
  });

  it('diz por que a ação pularia', () => {
    const linhas = linhasDoEnsaio(
      ['faltou_valor', 'data_invalida', 'valor_fora_do_formato'].map(faria => ({
        id: 'p1',
        tipo: 'acao',
        faria,
      })),
      fraseDe,
      t
    );

    expect(linhas.map(linha => linha.aviso)).toEqual([
      'AUTOMACAO_LIVRE.ENSAIO.ACAO_FALTOU_VALOR',
      'AUTOMACAO_LIVRE.ENSAIO.DATA_INVALIDA',
      'AUTOMACAO_LIVRE.ENSAIO.VALOR_FORA_DO_FORMATO',
    ]);
  });
});
