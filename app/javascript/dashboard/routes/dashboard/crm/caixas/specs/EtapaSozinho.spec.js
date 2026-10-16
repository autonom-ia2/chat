import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EtapaSozinho from '../components/EtapaSozinho.vue';
import { chaveDoModo, iaDeAssuntoLigada } from '../helpers/iaDeAssunto';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1676 — com a flag crm_avaliar_toda_mensagem da conta, a caixa de 1 funil tem
// a IA de assunto: "à mão" vira "quando entender o assunto" (o mesmo texto da
// caixa de vários funis) e "assim que chega" diz que a IA dá o nome. Sem a
// flag, os textos de sempre.
const conta = vi.hoisted(() => ({ ia: false }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    'accounts/getAccount': () => () => ({
      features: { crm_avaliar_toda_mensagem: conta.ia },
    }),
    getCurrentAccountId: () => 1,
  };
  return { useMapGetter: nome => computed(() => getters[nome]()) };
});

const render = (props = {}) =>
  mount(EtapaSozinho, {
    props: {
      umFunil: true,
      modo: 'chegou',
      funil: 'Vendas',
      etapa: 'Novo',
      pessoa: 'Ana',
      ...props,
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: false,
          messages: { en, pt_BR },
        }),
      ],
    },
  });

const opcao = (wrapper, modo) => wrapper.find(`[data-modo="${modo}"]`).text();

describe('EtapaSozinho', () => {
  beforeEach(() => {
    conta.ia = false;
  });

  it('without the flag keeps the single-pipeline texts as before', () => {
    const wrapper = render();

    expect(opcao(wrapper, 'chegou')).toContain(
      'Toda conversa nova vira um card, sem esperar.'
    );
    expect(opcao(wrapper, 'off')).toContain('Não fazer nada sozinho');
    expect(opcao(wrapper, 'off')).toContain('A equipe cria cada card à mão.');
  });

  it('with the flag: "by hand" becomes "when it understands", with the several-pipelines text', () => {
    conta.ia = true;
    const wrapper = render({ modo: 'off' });

    expect(opcao(wrapper, 'off')).toContain(
      'Criar o card quando entender o assunto'
    );
    expect(opcao(wrapper, 'off')).toContain(
      'O sistema lê a conversa, escolhe o funil certo e cria o card.'
    );
    expect(opcao(wrapper, 'off')).not.toContain('à mão');
    expect(wrapper.find('[data-exemplo] .i-lucide-hand').exists()).toBe(false);
    expect(wrapper.find('[data-exemplo]').text()).toContain(
      'O sistema entende que é Vendas e cria o card.'
    );
  });

  it('with the flag: "as soon as it arrives" says the AI names the card', () => {
    conta.ia = true;
    const wrapper = render();

    expect(opcao(wrapper, 'chegou')).toContain(
      'O card nasce com a primeira mensagem, e a IA dá o nome.'
    );
    expect(wrapper.find('[data-exemplo]').text()).toContain(
      'e a IA dá o nome quando entende o pedido'
    );
  });

  it('with the flag, "when it understands" in one pipeline shows the unclear-subject note and the pipeline AI warning', () => {
    conta.ia = true;
    const wrapper = render({ modo: 'off', funisSemIa: ['Vendas'] });

    expect(wrapper.find('[data-exemplo]').text()).toContain(
      'Se não der para entender o assunto'
    );
    expect(wrapper.find('[data-sem-ia]').exists()).toBe(true);
  });

  it('with the flag, "as soon as it arrives" also warns when the pipeline AI is off', () => {
    conta.ia = true;
    const wrapper = render({ funisSemIa: ['Vendas'] });

    expect(wrapper.find('[data-sem-ia]').exists()).toBe(true);
  });

  it('without the flag, one pipeline never shows the pipeline AI warning', () => {
    const wrapper = render({ modo: 'off', funisSemIa: ['Vendas'] });

    expect(wrapper.find('[data-sem-ia]').exists()).toBe(false);
  });

  it('with several pipelines the options stay the same, flag or not', () => {
    conta.ia = true;
    const wrapper = render({ umFunil: false, modo: 'off' });

    expect(opcao(wrapper, 'off')).toContain('Não fazer nada sozinho');
    expect(wrapper.find('[data-modo="suggest"]').exists()).toBe(true);
  });
});

describe('chaveDoModo', () => {
  it.each([
    ['off', true, true, 'AUTO'],
    ['chegou', true, true, 'CHEGOU_IA'],
    ['off', true, false, 'OFF'],
    ['chegou', true, false, 'CHEGOU'],
    ['off', false, true, 'OFF'],
    ['auto', false, true, 'AUTO'],
    ['suggest', false, false, 'SUGGEST'],
  ])('%s, one pipeline %s, flag %s -> %s', (modo, umFunil, ia, chave) => {
    expect(chaveDoModo(modo, umFunil, ia)).toBe(chave);
  });

  it('reads the flag from the account features', () => {
    expect(
      iaDeAssuntoLigada({ features: { crm_avaliar_toda_mensagem: true } })
    ).toBe(true);
    expect(iaDeAssuntoLigada({ features: {} })).toBe(false);
    expect(iaDeAssuntoLigada(null)).toBe(false);
  });
});
