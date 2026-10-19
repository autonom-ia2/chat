import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NovaConversaCaixaDoEmail from '../NovaConversaCaixaDoEmail.vue';
import {
  FORMATACAO_FIXA,
  REGUA_SO_NO_AA,
} from '../../conversa-canal/email/visualEmail';

// #1809 — a caixa do e-mail na gaveta "Escrever": a régua só no "Aa", sem o botão de
// imagem e sem o ✨ do Captain (não usamos).
const EditorFalso = defineComponent({
  name: 'WootEditor',
  props: { hiddenMenuOptions: { type: Array, default: () => [] } },
  setup: props => () =>
    h('div', {
      'data-editor-falso': '',
      'data-ocultos': props.hiddenMenuOptions.join(','),
    }),
});

const montar = () =>
  mount(NovaConversaCaixaDoEmail, {
    props: {
      canal: { id: 4, channelType: INBOX_TYPES.EMAIL },
      mensagem: 'Oi Marina',
    },
    global: {
      stubs: {
        WootEditor: EditorFalso,
        NovaConversaBarraDoEmail: {
          emits: ['update:formatacao'],
          template:
            '<button data-aa-falso @click="$emit(\'update:formatacao\', true)" />',
        },
        AttachmentPreviews: true,
        AvisoDeAssinatura: true,
        CampoDeEnderecos: true,
      },
    },
  });

describe('NovaConversaCaixaDoEmail (#1809)', () => {
  it('o editor do e-mail não mostra o ✨ do Captain nem o botão de imagem', () => {
    const editor = montar().findComponent(EditorFalso);
    expect(editor.props('hiddenMenuOptions')).toEqual([
      'copilot',
      'imageUpload',
    ]);
    expect(editor.attributes('enable-captain-tools')).toBeUndefined();
  });

  it('régua só com o "Aa": desligado esconde também a barra flutuante da seleção', async () => {
    const wrapper = montar();
    const caixa = () => wrapper.find('[data-caixa-do-email]').classes();
    expect(caixa()).toContain(REGUA_SO_NO_AA);
    await wrapper.find('[data-aa-falso]').trigger('click');
    expect(caixa()).not.toContain(REGUA_SO_NO_AA);
    expect(caixa()).toEqual(
      expect.arrayContaining(FORMATACAO_FIXA.split(' ').slice(0, 3))
    );
  });
});
