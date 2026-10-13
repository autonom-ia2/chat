import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import RichFrame from '../Frame.vue';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

const mountFrame = (template, content = 'Corpo da mensagem.') => {
  const TestHost = defineComponent({
    components: { RichFrame },
    setup() {
      provideMessageContext({
        content: ref(content),
        attachments: ref([]),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template,
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

describe('Frame', () => {
  it('mostra cabeçalho, corpo, rodapé e a interação, nessa ordem', () => {
    const wrapper = mountFrame(
      '<RichFrame bubble-name="rich-teste" header="Título" footer="Rodapé"><p>Interação</p></RichFrame>'
    );

    expect(wrapper.text()).toBe('TítuloCorpo da mensagem.\nRodapéInteração');
  });

  it('aceita cabeçalho próprio (imagem) no lugar do texto', () => {
    const wrapper = mountFrame(
      '<RichFrame bubble-name="rich-teste" header="Título"><template #header><img alt="Foto da unidade" /></template></RichFrame>'
    );

    expect(wrapper.find('img').attributes('alt')).toBe('Foto da unidade');
    expect(wrapper.text()).not.toContain('Título');
  });

  it('sem cabeçalho, corpo e rodapé mostra só a interação', () => {
    const wrapper = mountFrame(
      '<RichFrame bubble-name="rich-teste"><p>Interação</p></RichFrame>',
      null
    );

    expect(wrapper.text()).toBe('Interação');
  });
});
