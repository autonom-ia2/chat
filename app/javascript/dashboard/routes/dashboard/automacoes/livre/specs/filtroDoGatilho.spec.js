import { mount } from '@vue/test-utils';
import LivreCondicao from '../components/LivreCondicao.vue';
import { filtrosDoGatilho } from '../receita';
import { fraseDaCondicao, operadoresDoValor } from '../frases';
import { opcoesDosValores } from '../texto';
import pt from 'dashboard/i18n/locale/pt_BR';

// #2496 — o "Tipo da mensagem" só vale no "Só se" de "Quando chega uma
// mensagem": entra sugerido ao escolher o gatilho, sai quando ele muda, e o
// valor do campo anterior não vai junto para o novo.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const MENSAGEM = 'mensagem.criada';
const TIPO = { campo: { $valor: 'mensagem.tipo' }, op: 'igual' };
const RECEBIDA = { ...TIPO, valor: 'recebida' };
const PRIVADA = {
  campo: { $valor: 'mensagem.privada' },
  op: 'igual',
  valor: true,
};
const STATUS = {
  campo: { $valor: 'conversa.status' },
  op: 'igual',
  valor: 'open',
};

const CATALOGO = {
  gatilhos: [
    { tipo: 'conversa.resolvida', frase: 'RESOLVIDA' },
    { tipo: MENSAGEM, frase: 'MENSAGEM', filtro_sugerido: RECEBIDA },
  ],
  operadores: [
    {
      op: 'igual',
      pede_valor: true,
      frase: 'AUTOMACAO_LIVRE.OPERADORES.IGUAL',
    },
    { op: 'diferente', pede_valor: true, frase: 'DIFERENTE' },
    { op: 'contem', pede_valor: true, frase: 'CONTEM' },
  ],
  valores: [
    { caminho: 'conversa.status', frase: 'STATUS' },
    {
      caminho: 'mensagem.tipo',
      frase: 'AUTOMACAO_LIVRE.VALORES.MENSAGEM_TIPO',
      so_no_gatilho: MENSAGEM,
      opcoes: ['recebida', 'enviada', 'nota'].map(valor => ({
        valor,
        frase: `AUTOMACAO_LIVRE.VALOR_DA_MENSAGEM.${valor.toUpperCase()}`,
      })),
      operadores: [
        { op: 'igual', frase: 'AUTOMACAO_LIVRE.OPERADOR_DA_MENSAGEM.IGUAL' },
        {
          op: 'diferente',
          frase: 'AUTOMACAO_LIVRE.OPERADOR_DA_MENSAGEM.DIFERENTE',
        },
      ],
    },
    {
      caminho: 'mensagem.privada',
      frase: 'AUTOMACAO_LIVRE.VALORES.MENSAGEM_PRIVADA',
      so_no_gatilho: MENSAGEM,
      so_guia: true,
    },
  ],
  passos: [],
};

const ler = chave =>
  chave.split('.').reduce((nivel, parte) => nivel?.[parte], pt);
const tReal = (chave, valores = {}) =>
  Object.entries(valores).reduce(
    (texto, [nome, valor]) => texto.replace(`{${nome}}`, valor),
    ler(chave) ?? chave
  );

describe('o "Só se" acompanha o gatilho', () => {
  it('ao escolher "Quando chega uma mensagem", entra a sugestão', () => {
    const troca = filtrosDoGatilho([STATUS], MENSAGEM, CATALOGO);

    expect(troca).toEqual({
      filtros: [STATUS, RECEBIDA],
      entra: RECEBIDA,
      saem: [],
    });
  });

  it('não duplica a sugestão quando o "Só se" já olha a mensagem, nem pela privada', () => {
    expect(filtrosDoGatilho([PRIVADA], MENSAGEM, CATALOGO).entra).toBeNull();
    const nota = { ...TIPO, valor: 'nota' };
    expect(filtrosDoGatilho([nota], MENSAGEM, CATALOGO)).toEqual({
      filtros: [nota],
      entra: null,
      saem: [],
    });
  });

  it('em outro gatilho, a condição da mensagem sai, inclusive a do Guia', () => {
    const troca = filtrosDoGatilho(
      [STATUS, RECEBIDA, PRIVADA],
      'conversa.resolvida',
      CATALOGO
    );

    expect(troca).toEqual({
      filtros: [STATUS],
      entra: null,
      saem: [RECEBIDA, PRIVADA],
    });
  });

  it('condição composta com a mensagem sai inteira', () => {
    const composta = { todas: [STATUS, RECEBIDA] };

    expect(
      filtrosDoGatilho([composta], 'conversa.resolvida', CATALOGO)
    ).toEqual({
      filtros: [],
      entra: null,
      saem: [composta],
    });
  });

  it('sem filtros, num gatilho sem sugestão, nada muda', () => {
    expect(filtrosDoGatilho(undefined, 'conversa.resolvida', CATALOGO)).toEqual(
      {
        filtros: [],
        entra: null,
        saem: [],
      }
    );
  });
});

describe('o valor da mensagem na tela', () => {
  const caminhos = gatilho =>
    opcoesDosValores(
      CATALOGO,
      () => [],
      chave => chave,
      gatilho
    ).map(item => item.value);

  it('só aparece no "Só se" do gatilho dele; o do Guia nunca aparece', () => {
    expect(caminhos(MENSAGEM)).toEqual(['conversa.status', 'mensagem.tipo']);
    expect(caminhos('conversa.resolvida')).toEqual(['conversa.status']);
    expect(caminhos()).toEqual(['conversa.status']);
  });

  // G53: a Partida confere o "Só se" sem a mensagem que falhou; ela só vale
  // nos passos, e o editor não a oferece no filtro.
  it('a mensagem que falhou fica fora do "Só se" e entra nos passos', () => {
    const FALHOU = 'mensagem.falhou';
    const comFalhou = {
      ...CATALOGO,
      valores: [
        { caminho: 'conversa.status', frase: 'STATUS' },
        {
          caminho: 'falhou.texto',
          base: 'falhou',
          frase: 'FALHOU_TEXTO',
          so_nos_gatilhos: [FALHOU],
          so_nos_passos: true,
        },
      ],
    };
    const de = gatilho =>
      opcoesDosValores(
        comFalhou,
        () => [],
        chave => chave,
        gatilho
      ).map(item => item.value);

    expect(de(FALHOU)).toEqual(['conversa.status']);
    expect(de()).toEqual(['conversa.status', 'falhou.texto']);
  });

  it('compara só por "é" e "não é", e os outros campos por todos', () => {
    expect(
      operadoresDoValor('mensagem.tipo', CATALOGO).map(item => item.op)
    ).toEqual(['igual', 'diferente']);
    expect(operadoresDoValor('mensagem.tipo', CATALOGO)[0].pede_valor).toBe(
      true
    );
    expect(operadoresDoValor('conversa.status', CATALOGO)).toHaveLength(3);
  });

  it('lê em frase de leigo', () => {
    expect(fraseDaCondicao(RECEBIDA, CATALOGO, tReal)).toBe(
      'Tipo da mensagem é do cliente'
    );
    expect(
      fraseDaCondicao(
        { ...TIPO, op: 'diferente', valor: 'nota' },
        CATALOGO,
        tReal
      )
    ).toBe('Tipo da mensagem não é nota interna');
  });
});

describe('LivreCondicao', () => {
  const montar = (modelValue, gatilho = MENSAGEM) =>
    mount(LivreCondicao, {
      props: { modelValue, catalogo: CATALOGO, atributosDo: () => [], gatilho },
      global: {
        mocks: { $t: chave => chave },
        stubs: {
          Input: true,
          ChoiceSelect: {
            name: 'ChoiceSelect',
            props: {
              options: Array,
              modelValue: null,
              wrapSelected: Boolean,
            },
            emits: ['update:modelValue'],
            template: '<div data-escolha />',
          },
        },
      },
    });
  const escolhas = wrapper =>
    wrapper.findAllComponents({ name: 'ChoiceSelect' });

  // #2754: "O contato tem reunião marcada (em qualquer card)" não cabe numa
  // linha em 390 px; o campo fechado quebra linha em vez de cortar.
  it('o que olhar quebra linha no campo fechado; o operador não', () => {
    const [campo, operador] = escolhas(montar(STATUS));

    expect(campo.props('wrapSelected')).toBe(true);
    expect(operador.props('wrapSelected')).toBe(false);
  });

  it('trocar o campo para "Tipo da mensagem" não leva o valor do anterior', () => {
    const wrapper = montar(STATUS);

    escolhas(wrapper)[0].vm.$emit('update:modelValue', 'mensagem.tipo');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual(RECEBIDA);
  });

  it('trocar para campo aberto começa vazio, e o operador vira um que ele aceita', () => {
    const wrapper = montar({ ...TIPO, op: 'diferente', valor: 'nota' });

    escolhas(wrapper)[0].vm.$emit('update:modelValue', 'conversa.status');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
      campo: { $valor: 'conversa.status' },
      op: 'diferente',
      valor: '',
    });
  });

  it('a condição do Guia com a privada abre mostrando o que olha', () => {
    const wrapper = montar(PRIVADA);
    const campos = escolhas(wrapper)[0]
      .props('options')
      .map(item => item.value);

    expect(campos).toContain('mensagem.privada');
    expect(
      montar(STATUS)
        .findAllComponents({ name: 'ChoiceSelect' })[0]
        .props('options')
        .map(item => item.value)
    ).not.toContain('mensagem.privada');
  });
});
