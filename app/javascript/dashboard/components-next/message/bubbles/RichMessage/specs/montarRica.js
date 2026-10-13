import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

// Monta uma bolha de `types/` com o contexto da mensagem, como a conversa faz (P5: localização e contato).
export const montarRica = (
  Bolha,
  { content = '', sender = { name: 'Marina Lopes' }, richMessage = {} } = {}
) => {
  const TestHost = defineComponent({
    components: { Bolha },
    setup() {
      provideMessageContext({
        content: ref(content),
        sender: ref(sender),
        contentAttributes: ref({ richMessage }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Bolha />',
  });

  return mount(TestHost, {
    global: {
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};
