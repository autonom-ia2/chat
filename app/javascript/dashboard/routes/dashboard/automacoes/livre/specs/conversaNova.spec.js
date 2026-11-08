import { mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import { doAlvoDoGatilho } from '../catalogo';
import { fraseDoGatilho } from '../frases';

// #2680 — a caixa por onde a mensagem abre a conversa de quem ainda não tem uma:
// só nos gatilhos de card e de contato; vai como conversa_nova.caixa_id, sai
// com "Nenhuma" e fica ao trocar para outro gatilho que também pode não ter
// conversa. Com ela, o contato alcança os valores da conversa.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const GATILHOS = [
  { tipo: 'conversa.criada', alvo: 'Conversation', frase: 'CONVERSA_CRIADA' },
  { tipo: 'card.criado', alvo: 'Crm::Card', frase: 'CARD_CRIADO' },
  { tipo: 'card.ganho', alvo: 'Crm::Card', frase: 'CARD_GANHO' },
];
const CAIXAS = [{ value: 7, label: 'WhatsApp oficial' }];

const montar = modelValue =>
  mount(LivreGatilho, {
    props: { modelValue, gatilhos: GATILHOS, escolhas: { caixas: CAIXAS } },
    global: { mocks: { $t: chave => chave } },
  });
const daCaixa = wrapper =>
  wrapper
    .find('[data-parametro="conversa_nova"]')
    .findComponent({ name: 'ChoiceSelect' });
const emitido = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

describe('caixa da conversa nova no gatilho', () => {
  it('aparece no gatilho de card, com "Nenhuma" e as caixas que abrem conversa', () => {
    const opcoes = daCaixa(montar({ tipo: 'card.criado' })).props('options');

    expect(opcoes).toEqual([
      { value: '', label: 'AUTOMACAO_LIVRE.CONVERSA_NOVA.NENHUMA' },
      ...CAIXAS,
    ]);
  });

  it('não aparece no gatilho de conversa', () => {
    const wrapper = montar({ tipo: 'conversa.criada' });

    expect(wrapper.find('[data-parametro="conversa_nova"]').exists()).toBe(
      false
    );
  });

  it('a escolha vai como conversa_nova.caixa_id, e "Nenhuma" tira a chave', async () => {
    const wrapper = montar({ tipo: 'card.criado' });

    daCaixa(wrapper).vm.$emit('update:modelValue', 7);
    expect(emitido(wrapper)).toEqual({
      tipo: 'card.criado',
      conversa_nova: { caixa_id: 7 },
    });

    await wrapper.setProps({
      modelValue: { tipo: 'card.criado', conversa_nova: { caixa_id: 7 } },
    });
    daCaixa(wrapper).vm.$emit('update:modelValue', '');
    expect(emitido(wrapper)).toEqual({ tipo: 'card.criado' });
  });

  it('fica ao trocar para outro gatilho de card, e sai no de conversa', () => {
    const wrapper = montar({
      tipo: 'card.criado',
      conversa_nova: { caixa_id: 7 },
    });
    const tipo = wrapper.findAllComponents({ name: 'ChoiceSelect' })[0];

    tipo.vm.$emit('update:modelValue', 'card.ganho');
    expect(emitido(wrapper)).toEqual({
      tipo: 'card.ganho',
      conversa_nova: { caixa_id: 7 },
    });

    tipo.vm.$emit('update:modelValue', 'conversa.criada');
    expect(emitido(wrapper)).toEqual({ tipo: 'conversa.criada' });
  });
});

describe('valores com a conversa nova', () => {
  const catalogo = {
    gatilhos: [{ tipo: 'contato.data', alvo: 'Contact' }],
    alvos: { Contact: ['contato', 'envio'] },
    valores: [
      { caminho: 'conversa.status', base: 'conversa' },
      { caminho: 'conversa.cliente_respondeu', base: 'conversa' },
      { caminho: 'contato.nome', base: 'contato' },
      { caminho: 'envio.situacao', base: 'envio' },
    ],
  };
  const caminhos = dados => dados.valores.map(item => item.caminho);

  it('sem a caixa, o contato só lê o contato, o envio e a resposta do cliente', () => {
    expect(caminhos(doAlvoDoGatilho(catalogo, 'contato.data'))).toEqual([
      'conversa.cliente_respondeu',
      'contato.nome',
      'envio.situacao',
    ]);
  });

  it('com a caixa, o contato alcança a conversa que ela abre', () => {
    expect(caminhos(doAlvoDoGatilho(catalogo, 'contato.data', true))).toEqual([
      'conversa.status',
      'conversa.cliente_respondeu',
      'contato.nome',
      'envio.situacao',
    ]);
  });
});

describe('frase do gatilho com a conversa nova', () => {
  const catalogo = {
    gatilhos: [
      { tipo: 'card.criado', alvo: 'Crm::Card', frase: 'CARD_CRIADO' },
    ],
  };
  const t = (chave, valores) =>
    valores ? `${chave} ${Object.values(valores).join(' | ')}` : chave;

  it('diz a caixa escolhida; sem o nome dela, fica a frase de sempre', () => {
    const gatilho = { tipo: 'card.criado', conversa_nova: { caixa_id: 7 } };

    expect(
      fraseDoGatilho(gatilho, catalogo, t, { caixa: { 7: 'WhatsApp oficial' } })
    ).toBe(
      'AUTOMACAO_LIVRE.CONVERSA_NOVA.NA_FRASE CARD_CRIADO | WhatsApp oficial'
    );
    expect(fraseDoGatilho(gatilho, catalogo, t, {})).toBe('CARD_CRIADO');
  });

  // G7 (#2635): o recorrente de card também pode abrir a conversa.
  it('no recorrente de card, diz a caixa depois do quando', () => {
    const recorrente = {
      tipo: 'card.recorrente',
      alvo: 'Crm::Card',
      frase: 'CARD_RECORRENTE',
      parametros: [{ nome: 'frequencia', peca: 'frequencia' }],
    };
    const gatilho = {
      tipo: 'card.recorrente',
      frequencia: 'diaria',
      hora: 8,
      conversa_nova: { caixa_id: 7 },
    };

    expect(
      fraseDoGatilho(gatilho, { gatilhos: [recorrente] }, t, {
        caixa: { 7: 'WhatsApp oficial' },
      })
    ).toBe(
      'AUTOMACAO_LIVRE.CONVERSA_NOVA.NA_FRASE AUTOMACAO_LIVRE.GATILHO_RECORRENTE.FRASE.DIARIA  | 8 | AUTOMACAO_LIVRE.GATILHO_RECORRENTE.CARDS | WhatsApp oficial'
    );
  });
});
