import { mount } from '@vue/test-utils';
import LivreDecidirDeNovo from '../components/LivreDecidirDeNovo.vue';
import { deNovoPronto, esperasAnteriores, marcadosComPassos } from '../ia';
import { fraseDoPasso } from '../frases';
import { linhasDoEnsaio } from '../ensaio';
import pt from 'dashboard/i18n/locale/pt_BR';

// #2414 G46 — o laço dos documentos (exemplo 14): o caminho marcado roda os
// passos dele e volta a um "esperar até" de antes ("voltar a esperar em").
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const textoDe = chave =>
  chave.split('.').reduce((no, parte) => no?.[parte], pt);
const tReal = (chave, valores) =>
  Object.entries(valores || {}).reduce(
    (texto, [nome, valor]) => texto.replaceAll(`{${nome}}`, valor),
    textoDe(chave) ?? chave
  );

const documento = (valor = true, op = 'igual') => ({
  campo: { $valor: 'conversa.cliente_mandou_documento' },
  op,
  valor,
});
const espera = (id, condicao = documento(), seVencer = []) => ({
  id,
  tipo: 'esperar_ate',
  condicao,
  prazo: { valor: 2, unidade: 'dias' },
  se_vencer: seVencer,
});
const caminho = (nome, chave, passos = []) => ({
  nome,
  chave,
  descricao: 'x',
  passos,
});
const pedido = { id: 'pede', tipo: 'parar' };
const decidir = deNovo => ({
  id: 'decide',
  tipo: 'decidir',
  pergunta: 'O que chegou?',
  caminhos: [
    caminho('Falta algo', 'falta_algo', [pedido]),
    caminho('Tudo recebido', 'tudo_recebido'),
  ],
  nenhum: [],
  ...(deNovo && { de_novo: deNovo }),
});
const ESPERAS = [{ value: 'espera_doc', label: 'Espera o documento' }];
const UM_DIA = { valor: 24, unidade: 'horas' };

const montar = (modelValue, esperas = ESPERAS) =>
  mount(LivreDecidirDeNovo, {
    props: {
      rotulo: 'DE_NOVO',
      modelValue,
      passo: decidir(modelValue),
      unidades: [],
      esperas,
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: { Switch: true, LivreDuracao: true, ChoiceSelect: true },
    },
  });

describe('LivreDecidirDeNovo: voltar a esperar em', () => {
  it('escolher o "esperar até" troca o prazo pelo desde e esconde o prazo', async () => {
    const wrapper = montar({ caminhos: ['falta_algo'], prazo: UM_DIA });
    const escolha = wrapper.findComponent({ name: 'ChoiceSelect' });
    expect(escolha.props('options')).toEqual([
      { value: '', label: 'AUTOMACAO_LIVRE.IA.DE_NOVO.NAO_VOLTA' },
      ...ESPERAS,
    ]);
    expect(wrapper.findComponent({ name: 'LivreDuracao' }).exists()).toBe(true);

    await escolha.vm.$emit('update:modelValue', 'espera_doc');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { caminhos: ['falta_algo'], desde: 'espera_doc' },
    ]);
  });

  it('com desde, o caminho marcado pode ter passos e o prazo some; "não volta" traz o prazo de volta', async () => {
    const wrapper = montar({ caminhos: ['falta_algo'], desde: 'espera_doc' });
    expect(wrapper.findAll('[data-aviso-de-novo]')).toHaveLength(0);
    expect(wrapper.findComponent({ name: 'LivreDuracao' }).exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('AUTOMACAO_LIVRE.IA.DE_NOVO.DICA_VOLTA');

    await wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', '');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { caminhos: ['falta_algo'], prazo: UM_DIA },
    ]);
  });

  it('avisa quando o passo escolhido para voltar não serve mais', () => {
    const wrapper = montar({ caminhos: ['falta_algo'], desde: 'sumiu' });
    expect(wrapper.findAll('[data-aviso-de-novo]').map(p => p.text())).toEqual([
      'AUTOMACAO_LIVRE.IA.DE_NOVO.VOLTA_FORA',
    ]);
  });

  it('sem "esperar até" de antes, o campo não aparece', () => {
    const wrapper = montar({ caminhos: ['falta_algo'], prazo: UM_DIA }, []);
    expect(wrapper.find('[data-de-novo-volta]').exists()).toBe(false);
  });
});

describe('ia.js: o desde', () => {
  it('esperasAnteriores: só os "esperar até" de antes, na mesma lista, que esperam o cliente', () => {
    const decide = decidir({ caminhos: ['falta_algo'], desde: 'espera_doc' });
    const receita = {
      passos: [
        espera('longe'),
        { id: 'lista', tipo: 'mensagem' },
        espera('equipe', {
          campo: { $valor: 'conversa.equipe_respondeu' },
          op: 'igual',
          valor: true,
        }),
        espera('diferente', documento(true, 'diferente')),
        espera('espera_doc', documento(), [espera('dentro')]),
        decide,
        espera('depois'),
      ],
    };

    expect(esperasAnteriores(receita, 'decide').map(item => item.id)).toEqual([
      'espera_doc',
      'longe',
    ]);
    expect(esperasAnteriores(null, 'decide')).toEqual([]);
  });

  it('marcadosComPassos e deNovoPronto aceitam passos e dispensam o prazo com desde', () => {
    const comDesde = decidir({ caminhos: ['falta_algo'], desde: 'espera_doc' });
    expect(marcadosComPassos(comDesde)).toEqual([]);
    expect(deNovoPronto(comDesde)).toBe(true);
    expect(deNovoPronto(decidir({ caminhos: ['falta_algo'] }))).toBe(false);
  });
});

describe('frase e ensaio do caminho que volta', () => {
  const catalogo = {
    valores: [],
    unidades: [],
    passos: [{ tipo: 'decidir', frase: 'D', campos: [] }],
  };

  it('a frase diz que o caminho volta a esperar', () => {
    const passo = decidir({
      caminhos: ['falta_algo', 'nenhum'],
      desde: 'espera_doc',
    });
    expect(fraseDoPasso(passo, catalogo, tReal)).toBe(
      'A IA decide: “O que chegou?” (2 caminhos); se Falta algo e nenhum se aplica, faz o caminho e volta a esperar no “esperar até” de antes'
    );
  });

  it('no ensaio, o caminho que volta mostra os passos dele e para onde volta', () => {
    const no = {
      id: 'decide',
      tipo: 'decidir',
      faria: 'decidir',
      ramos: [
        {
          chave: 'falta_algo',
          nome: 'Falta algo',
          volta: 'espera_doc',
          passos: [{ id: 'pede', tipo: 'parar', faria: 'parar' }],
        },
        { chave: 'nenhum', volta: 'espera_doc', passos: [] },
      ],
    };

    const linhas = linhasDoEnsaio([no], id => `frase ${id}`, tReal).slice(1);

    expect(linhas.map(({ nivel, texto }) => [nivel, texto])).toEqual([
      [1, 'Se a IA escolher "Falta algo":'],
      [2, 'frase pede'],
      [2, 'Depois volta a esperar: frase espera_doc'],
      [1, 'Se nenhum se aplicar:'],
      [2, 'Depois volta a esperar: frase espera_doc'],
    ]);
  });
});
