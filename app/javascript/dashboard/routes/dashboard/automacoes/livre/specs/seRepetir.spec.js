import { mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import { doAlvoDoGatilho } from '../catalogo';
import { opcoesDosValores } from '../texto';
import { fraseDoGatilho } from '../frases';

// #2414 G50 — o gatilho que acontece de novo com a automação ainda esperando no
// mesmo card: "Não começa outra vez" (sem a chave, como sempre foi) ou "Começa
// outra vez" (`se_repetir: comeca_outra`). Só no gatilho que o catálogo marca;
// a escolha é um ChoiceSelect, nunca <select>. O valor "entrou de novo na
// etapa" só aparece na condição do "esperar até" do gatilho de etapa.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const GATILHOS = [
  {
    tipo: 'card.entrou_na_etapa',
    alvo: 'Crm::Card',
    frase: 'CARD_ENTROU_NA_ETAPA',
    se_repetir: true,
  },
  {
    tipo: 'card.ganho',
    alvo: 'Crm::Card',
    frase: 'CARD_GANHO',
    se_repetir: true,
  },
  { tipo: 'mensagem.criada', alvo: 'Conversation', frase: 'MENSAGEM_CRIADA' },
];

const montar = modelValue =>
  mount(LivreGatilho, {
    props: { modelValue, gatilhos: GATILHOS, escolhas: {} },
    global: { mocks: { $t: chave => chave } },
  });
const daRepeticao = wrapper =>
  wrapper
    .find('[data-parametro="se_repetir"]')
    .findComponent({ name: 'ChoiceSelect' });
const emitido = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

describe('se o gatilho acontecer de novo (G50)', () => {
  it('aparece no gatilho que aceita, com as duas escolhas e "Não começa outra vez" marcado', () => {
    const escolha = daRepeticao(montar({ tipo: 'card.entrou_na_etapa' }));

    expect(escolha.props('options')).toEqual([
      { value: 'ignora', label: 'AUTOMACAO_LIVRE.SE_REPETIR.IGNORA' },
      {
        value: 'comeca_outra',
        label: 'AUTOMACAO_LIVRE.SE_REPETIR.COMECA_OUTRA',
      },
    ]);
    expect(escolha.props('modelValue')).toBe('ignora');
  });

  it('não aparece na mensagem nova', () => {
    const wrapper = montar({ tipo: 'mensagem.criada' });

    expect(wrapper.find('[data-parametro="se_repetir"]').exists()).toBe(false);
  });

  it('"Começa outra vez" vai como se_repetir, e "Não começa" tira a chave', async () => {
    const wrapper = montar({ tipo: 'card.entrou_na_etapa', etapa_id: 4 });

    daRepeticao(wrapper).vm.$emit('update:modelValue', 'comeca_outra');
    expect(emitido(wrapper)).toEqual({
      tipo: 'card.entrou_na_etapa',
      etapa_id: 4,
      se_repetir: 'comeca_outra',
    });

    await wrapper.setProps({
      modelValue: {
        tipo: 'card.entrou_na_etapa',
        etapa_id: 4,
        se_repetir: 'comeca_outra',
      },
    });
    daRepeticao(wrapper).vm.$emit('update:modelValue', 'ignora');
    expect(emitido(wrapper)).toEqual({
      tipo: 'card.entrou_na_etapa',
      etapa_id: 4,
    });
  });

  it('fica ao trocar para outro gatilho que aceita, e sai no que não aceita', () => {
    const wrapper = montar({
      tipo: 'card.entrou_na_etapa',
      etapa_id: 4,
      se_repetir: 'comeca_outra',
    });
    const tipo = wrapper.findAllComponents({ name: 'ChoiceSelect' })[0];

    tipo.vm.$emit('update:modelValue', 'card.ganho');
    expect(emitido(wrapper)).toEqual({
      tipo: 'card.ganho',
      se_repetir: 'comeca_outra',
    });

    tipo.vm.$emit('update:modelValue', 'mensagem.criada');
    expect(emitido(wrapper)).toEqual({ tipo: 'mensagem.criada' });
  });

  it('a frase do gatilho diz que começa outra vez', () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' | ')}` : chave;
    const catalogo = { gatilhos: [{ ...GATILHOS[1], frase: 'CARD_GANHO' }] };

    expect(
      fraseDoGatilho(
        { tipo: 'card.ganho', se_repetir: 'comeca_outra' },
        catalogo,
        t
      )
    ).toBe('AUTOMACAO_LIVRE.SE_REPETIR.NA_FRASE CARD_GANHO');
    expect(fraseDoGatilho({ tipo: 'card.ganho' }, catalogo, t)).toBe(
      'CARD_GANHO'
    );
  });
});

describe('valor "entrou de novo na etapa" (G50)', () => {
  const catalogo = {
    gatilhos: GATILHOS,
    alvos: { 'Crm::Card': ['card', 'conversa', 'contato'] },
    valores: [
      { caminho: 'card.status', base: 'card', frase: 'STATUS' },
      {
        caminho: 'card.entrou_de_novo',
        base: 'card',
        frase: 'ENTROU',
        so_na_espera: true,
        so_nos_gatilhos: ['card.entrou_na_etapa'],
      },
    ],
  };
  const caminhos = (tipo, naEspera) =>
    opcoesDosValores(
      doAlvoDoGatilho(catalogo, tipo),
      () => [],
      chave => chave,
      null,
      naEspera
    ).map(item => item.value);

  it('só na condição do "esperar até" do gatilho de etapa', () => {
    expect(caminhos('card.entrou_na_etapa', true)).toEqual([
      'card.status',
      'card.entrou_de_novo',
    ]);
    expect(caminhos('card.entrou_na_etapa', false)).toEqual(['card.status']);
    expect(caminhos('card.ganho', true)).toEqual(['card.status']);
  });
});
