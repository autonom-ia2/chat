import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

export const CAIXA_ID = 9;

// Caixas como o store do painel as devolve (`inboxes/getInboxById`), para a bolha saber o canal.
export const CAIXAS = {
  whatsappCloud: {
    id: CAIXA_ID,
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  },
  whatsapp360dialog: {
    id: CAIXA_ID,
    channel_type: 'Channel::Whatsapp',
    provider: 'default',
  },
};

// Monta uma bolha de `types/` com o contexto da mensagem, como a conversa faz (P5: localização e contato).
export const montarRica = (
  Bolha,
  {
    content = '',
    sender = { name: 'Marina Lopes' },
    richMessage = {},
    inbox = CAIXAS.whatsappCloud,
  } = {}
) => {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ inbox_id: CAIXA_ID }),
      'inboxes/getInboxById': () => id => (id === CAIXA_ID ? inbox : {}),
    },
  });

  const TestHost = defineComponent({
    components: { Bolha },
    setup() {
      provideMessageContext({
        content: ref(content),
        sender: ref(sender),
        inboxId: ref(CAIXA_ID),
        contentAttributes: ref({ richMessage }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Bolha />',
  });

  return mount(TestHost, {
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
