import { mount } from '@vue/test-utils';
import LivreDecidirDeNovo from '../components/LivreDecidirDeNovo.vue';
import { deNovoPronto } from '../ia';
import { fraseDoPasso } from '../frases';
import { linhasDoEnsaio } from '../ensaio';
import pt from 'dashboard/i18n/locale/pt_BR';

// #2414 G31 — "a cada resposta da Ana, a IA decide": o "decidir" que espera a
// próxima resposta e decide de novo quando a IA escolhe "Ainda conversando".
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const textoDe = chave =>
  chave.split('.').reduce((no, parte) => no?.[parte], pt);
// Plural do vue-i18n: "hora | horas".
const tReal = (chave, valores, n) => {
  const formas = (textoDe(chave) ?? chave).split(' | ');
  const forma = n === undefined || n === 1 ? formas[0] : formas.at(-1);
  return Object.entries(valores || {}).reduce(
    (texto, [nome, valor]) => texto.replaceAll(`{${nome}}`, valor),
    forma
  );
};

const caminho = (nome, chave, passos = []) => ({
  nome,
  chave,
  descricao: 'x',
  passos,
});
const marcador = { id: 'p9', tipo: 'parar' };
const decidir = deNovo => ({
  id: 'p1',
  tipo: 'decidir',
  pergunta: 'O que a Ana quer?',
  caminhos: [
    caminho('Quer visitar', 'quer_visitar', [marcador]),
    caminho('Ainda conversando', 'ainda_conversando'),
  ],
  ...(deNovo && { de_novo: deNovo }),
});
const DUAS_HORAS = { valor: 2, unidade: 'horas' };
const UM_DIA = { valor: 24, unidade: 'horas' };

const unidades = ['minutos', 'horas', 'dias'].map(item => ({
  valor: item,
  frase: `AUTOMACAO_LIVRE.UNIDADES.${item.toUpperCase()}`,
}));

const montar = (modelValue, passo = decidir(modelValue)) =>
  mount(LivreDecidirDeNovo, {
    props: { rotulo: 'DE_NOVO', modelValue, passo, unidades },
    global: {
      mocks: { $t: chave => chave },
      stubs: { Switch: true, LivreDuracao: true },
    },
  });

describe('LivreDecidirDeNovo', () => {
  it('ligado, nasce sem caminho marcado e com o prazo de 24 horas', async () => {
    const wrapper = montar(null);
    expect(wrapper.find('[data-de-novo-caminhos]').exists()).toBe(false);

    await wrapper
      .findComponent({ name: 'Switch' })
      .vm.$emit('update:modelValue', true);

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { caminhos: [], prazo: UM_DIA },
    ]);
  });

  it('desligado, sai da receita', async () => {
    const wrapper = montar({
      caminhos: ['ainda_conversando'],
      prazo: DUAS_HORAS,
    });

    await wrapper
      .findComponent({ name: 'Switch' })
      .vm.$emit('update:modelValue', false);

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([null]);
  });

  it('marca os caminhos por botões de 44 px, com "Nenhum se aplica" no fim', async () => {
    const wrapper = montar({ caminhos: [], prazo: DUAS_HORAS });
    const botoes = wrapper.findAll('[data-de-novo-caminhos] button');

    expect(botoes.map(botao => botao.text())).toEqual([
      'Quer visitar',
      'Ainda conversando',
      'AUTOMACAO_LIVRE.CAMPOS.NENHUM',
    ]);
    expect(botoes.every(botao => botao.classes('min-h-11'))).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);

    await botoes[1].trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { caminhos: ['ainda_conversando'], prazo: DUAS_HORAS },
    ]);
  });

  it('avisa quando o caminho marcado tem passos e quando todos estão marcados', () => {
    const comPassos = montar({ caminhos: ['quer_visitar'], prazo: DUAS_HORAS });
    expect(
      comPassos.findAll('[data-aviso-de-novo]').map(p => p.text())
    ).toEqual(['AUTOMACAO_LIVRE.IA.DE_NOVO.COM_PASSOS']);

    const todos = montar(
      { caminhos: ['quer_visitar', 'ainda_conversando'], prazo: DUAS_HORAS },
      {
        ...decidir(),
        caminhos: [caminho('A', 'a'), caminho('B', 'b')],
        de_novo: { caminhos: ['a', 'b'], prazo: DUAS_HORAS },
      }
    );
    expect(todos.findAll('[data-aviso-de-novo]').map(p => p.text())).toEqual([
      'AUTOMACAO_LIVRE.IA.DE_NOVO.TODOS',
    ]);
  });
});

describe('deNovoPronto', () => {
  it.each([
    ['desligado', decidir(), true],
    [
      'o exemplo 2',
      decidir({ caminhos: ['ainda_conversando'], prazo: DUAS_HORAS }),
      true,
    ],
    [
      'sem caminho marcado',
      decidir({ caminhos: [], prazo: DUAS_HORAS }),
      false,
    ],
    [
      'sem prazo',
      decidir({ caminhos: ['ainda_conversando'], prazo: { unidade: 'horas' } }),
      false,
    ],
    [
      'caminho marcado com passos',
      decidir({ caminhos: ['quer_visitar'], prazo: DUAS_HORAS }),
      false,
    ],
    [
      'caminho que não existe mais',
      decidir({ caminhos: ['sumiu'], prazo: DUAS_HORAS }),
      false,
    ],
    [
      '"nenhum" com passos no galho',
      {
        ...decidir({ caminhos: ['nenhum'], prazo: DUAS_HORAS }),
        nenhum: [marcador],
      },
      false,
    ],
  ])('%s: %s', (_nome, passo, pronto) => {
    expect(deNovoPronto(passo)).toBe(pronto);
  });
});

describe('frase e ensaio do decidir que decide de novo', () => {
  const catalogo = {
    valores: [],
    unidades,
    passos: [{ tipo: 'decidir', frase: 'D', campos: [] }],
  };

  it('a frase diz quais caminhos esperam e por quanto tempo', () => {
    const passo = decidir({
      caminhos: ['ainda_conversando', 'nenhum'],
      prazo: DUAS_HORAS,
    });

    expect(fraseDoPasso(passo, catalogo, tReal)).toBe(
      'A IA decide: “O que a Ana quer?” (2 caminhos); se Ainda conversando e nenhum se aplica, espera a próxima resposta (até 2 horas) e decide de novo; sem resposta no prazo, encerra sem mandar nada'
    );
    expect(fraseDoPasso(decidir(), catalogo, tReal)).toBe(
      'A IA decide: “O que a Ana quer?” (2 caminhos)'
    );
  });

  it('no ensaio, o caminho que decide de novo espera a próxima resposta e diz que, sem ela, encerra', () => {
    const no = {
      id: 'p1',
      tipo: 'decidir',
      faria: 'decidir',
      ramos: [
        { chave: 'quer_visitar', nome: 'Quer visitar', passos: [] },
        {
          chave: 'ainda_conversando',
          nome: 'Ainda conversando',
          de_novo: true,
          passos: [],
        },
        { chave: 'nenhum', de_novo: true, passos: [] },
      ],
    };

    const linhas = linhasDoEnsaio([no], id => `frase ${id}`, tReal).slice(1);

    expect(linhas.map(({ nivel, texto }) => [nivel, texto])).toEqual([
      [1, 'Se a IA escolher "Quer visitar":'],
      [
        1,
        'Se a IA escolher "Ainda conversando": espera a próxima resposta e decide de novo. Sem resposta no prazo, encerra sem mandar nada.',
      ],
      [
        1,
        'Se nenhum se aplicar: espera a próxima resposta e decide de novo. Sem resposta no prazo, encerra sem mandar nada.',
      ],
    ]);
  });
});
