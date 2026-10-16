import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import Poll from '../types/Poll.vue';
import { pollVoteFor } from '../pollAnswer.js';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_TYPES, MESSAGE_VARIANTS } from '../../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const ID_ENQUETE = 70;
const ENQUETE = {
  type: 'poll',
  options: [
    { id: 'sim', title: 'Sim' },
    { id: 'nao', title: 'Não' },
  ],
};

// O voto como a loja guarda (snake_case): incoming com `selected_options`, ou a atividade escondida do voto retirado.
const voto = (id, selected, messageType = MESSAGE_TYPES.INCOMING) => ({
  id,
  message_type: messageType,
  content_attributes: {
    in_reply_to: ID_ENQUETE,
    selected_options: selected,
    ...(selected[0] ? { selected_option: selected[0] } : { c2y_hidden: true }),
  },
});

const montar = (messages, richMessage = ENQUETE) => {
  const store = createStore({
    getters: { getSelectedChat: () => ({ messages }) },
  });
  const Host = defineComponent({
    components: { Poll },
    setup() {
      provideMessageContext({
        id: ref(ID_ENQUETE),
        content: ref('Vem amanhã?'),
        contentAttributes: ref({ richMessage }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Poll />',
  });
  return mount(Host, {
    global: {
      plugins: [store],
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

describe('bolha da enquete', () => {
  it('mostra a pergunta e as opções, sem voto carregado', () => {
    const wrapper = montar([]);

    expect(wrapper.text()).toContain('Vem amanhã?');
    expect(wrapper.findAll('[data-poll-option]').map(li => li.text())).toEqual([
      'Sim',
      'Não',
    ]);
    expect(wrapper.text()).toContain('Enquete: uma resposta');
    expect(wrapper.find('[data-poll-vote]').exists()).toBe(false);
  });

  it('mostra o voto mais recente, que troca quando o cliente muda o voto', () => {
    const sim = { id: 'sim', title: 'Sim' };
    const nao = { id: 'nao', title: 'Não' };

    expect(
      montar([voto(80, [sim])])
        .find('[data-poll-vote]')
        .text()
    ).toBe('Votou: Sim');
    expect(
      montar([voto(80, [sim]), voto(81, [nao])])
        .find('[data-poll-vote]')
        .text()
    ).toBe('Votou: Não');
  });

  it('volta a "Sem voto" quando o cliente retira o voto', () => {
    const sim = { id: 'sim', title: 'Sim' };
    const wrapper = montar([
      voto(80, [sim]),
      voto(81, [], MESSAGE_TYPES.ACTIVITY),
    ]);

    expect(wrapper.find('[data-poll-vote]').text()).toBe('Sem voto');
  });

  it('lista todas as marcadas na enquete de várias respostas', () => {
    const wrapper = montar(
      [
        voto(80, [
          { id: 'sim', title: 'Sim' },
          { id: 'nao', title: 'Não' },
        ]),
      ],
      { ...ENQUETE, multiple: true }
    );

    expect(wrapper.text()).toContain('Enquete: uma ou mais respostas');
    expect(wrapper.find('[data-poll-vote]').text()).toBe('Votou: Sim, Não');
  });
});

describe('pollVoteFor', () => {
  it('ignora mensagens de saída e respostas a outra mensagem', () => {
    expect(
      pollVoteFor(ID_ENQUETE, [
        { ...voto(1, [{ id: 'sim' }]), message_type: MESSAGE_TYPES.OUTGOING },
        {
          ...voto(2, [{ id: 'sim' }]),
          content_attributes: { in_reply_to: 3 },
        },
      ])
    ).toBeNull();
  });

  it('aceita a escolha antiga sem selected_options', () => {
    expect(
      pollVoteFor(ID_ENQUETE, [
        {
          id: 1,
          message_type: MESSAGE_TYPES.INCOMING,
          content_attributes: {
            in_reply_to: ID_ENQUETE,
            selected_option: { id: 'sim', title: 'Sim' },
          },
        },
      ])
    ).toEqual([{ id: 'sim', title: 'Sim' }]);
  });
});
