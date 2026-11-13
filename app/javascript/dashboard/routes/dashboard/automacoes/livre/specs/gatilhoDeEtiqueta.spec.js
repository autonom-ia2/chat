import { mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import LivreSelecao from '../components/LivreSelecao.vue';
import { fraseDoGatilho } from '../frases';

// G10 (F8.7) — a etiqueta posta ou tirada no editor: escolhe a etiqueta da
// conta pelo nome, e a frase diz o nome. F8.3: a troca de quem atende a
// conversa não pede nada.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));

const ETIQUETA = {
  nome: 'etiqueta',
  peca: 'etiqueta',
  obrigatorio: true,
  frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.ETIQUETA',
};
const GATILHOS = [
  {
    tipo: 'conversa.etiqueta_posta',
    alvo: 'Conversation',
    frase: 'AUTOMACAO_LIVRE.GATILHOS.CONVERSA_ETIQUETA_POSTA',
    grupo: 'conversa',
    parametros: [ETIQUETA],
  },
  {
    tipo: 'contato.etiqueta_tirada',
    alvo: 'Contact',
    frase: 'AUTOMACAO_LIVRE.GATILHOS.CONTATO_ETIQUETA_TIRADA',
    grupo: 'contato',
    requer: 'automacao_gatilhos',
    parametros: [ETIQUETA],
  },
  {
    tipo: 'conversa.responsavel_mudou',
    alvo: 'Conversation',
    frase: 'AUTOMACAO_LIVRE.GATILHOS.CONVERSA_RESPONSAVEL_MUDOU',
    grupo: 'conversa',
  },
  {
    tipo: 'card.recorrente',
    alvo: 'Crm::Card',
    frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_RECORRENTE',
    grupo: 'tempo',
    parametros: [
      {
        nome: 'selecao',
        peca: 'selecao',
        obrigatorio: true,
        frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.SELECAO',
      },
    ],
  },
];
const CATALOGO = { gatilhos: GATILHOS };
const OPCOES = {
  pessoa: [{ value: 7, label: 'Ana' }],
  etiquetaPorNome: [
    { value: 'vip', label: 'vip' },
    { value: 'boleto', label: 'boleto' },
  ],
};

const montar = modelValue =>
  mount(LivreGatilho, {
    props: { modelValue, gatilhos: GATILHOS, escolhas: {}, opcoes: OPCOES },
    global: { mocks: { $t: chave => chave } },
  });
const ultimo = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];
const seletorDaEtiqueta = wrapper =>
  wrapper
    .find('[data-parametro="etiqueta"]')
    .findComponent({ name: 'ChoiceSelect' });
const t = (chave, valores) =>
  valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;

describe('gatilho de etiqueta', () => {
  it('oferece as etiquetas da conta pelo nome e guarda o nome', () => {
    const wrapper = montar({ tipo: 'conversa.etiqueta_posta' });
    const seletor = seletorDaEtiqueta(wrapper);

    expect(seletor.props('options')).toEqual(OPCOES.etiquetaPorNome);
    seletor.vm.$emit('update:modelValue', 'vip');
    expect(ultimo(wrapper)).toEqual({
      tipo: 'conversa.etiqueta_posta',
      etiqueta: 'vip',
    });
  });

  it('no contato também pede a etiqueta', () => {
    const wrapper = montar({ tipo: 'contato.etiqueta_tirada' });

    expect(seletorDaEtiqueta(wrapper).exists()).toBe(true);
  });

  it('a troca de quem atende a conversa não pede nada', () => {
    const wrapper = montar({ tipo: 'conversa.responsavel_mudou' });

    expect(wrapper.find('[data-parametro="etiqueta"]').exists()).toBe(false);
    expect(wrapper.find('[data-parametro="funil_id"]').exists()).toBe(false);
  });

  // As escolhas da conta chegam à seleção do recorrente (o nome do seletor de
  // tipos não esconde mais a prop).
  it('a seleção do recorrente recebe as escolhas da conta', () => {
    const wrapper = montar({ tipo: 'card.recorrente', selecao: {} });

    expect(wrapper.findComponent(LivreSelecao).props('opcoes')).toEqual(OPCOES);
  });

  it('a frase diz o nome da etiqueta; sem ela, a frase do catálogo', () => {
    expect(
      fraseDoGatilho(
        { tipo: 'conversa.etiqueta_posta', etiqueta: 'vip' },
        CATALOGO,
        t,
        {}
      )
    ).toBe('AUTOMACAO_LIVRE.GATILHO_COM.CONVERSA_ETIQUETA_POSTA vip');
    expect(
      fraseDoGatilho({ tipo: 'contato.etiqueta_tirada' }, CATALOGO, t, {})
    ).toBe('AUTOMACAO_LIVRE.GATILHOS.CONTATO_ETIQUETA_TIRADA');
  });
});
