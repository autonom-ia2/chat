import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NovaConversaCaixaDoEmail from '../NovaConversaCaixaDoEmail.vue';
import { esquecerDisponibilidade } from '../../conversa-canal/email/useIaDoEmail';
import {
  FORMATACAO_FIXA,
  REGUA_SO_NO_AA,
} from '../../conversa-canal/email/visualEmail';

const estado = vi.hoisted(() => ({
  alerta: vi.fn(),
  api: { status: vi.fn(), run: vi.fn(), runText: vi.fn() },
}));

vi.mock('dashboard/api/autonomiaCopilot', () => ({ default: estado.api }));
vi.mock('dashboard/composables', () => ({ useAlert: estado.alerta }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: nome =>
      computed(() =>
        nome === 'globalConfig/get'
          ? { crmKanbanEnabled: true, crmCopilotEnabled: true }
          : 7
      ),
  };
});

// #1809 — a caixa do e-mail na gaveta "Escrever": a régua só no "Aa", sem o botão de
// imagem. #1872 — o ✨ com a IA do cliente (copiloto da Autonom.ia), nunca o Captain.
const EditorFalso = defineComponent({
  name: 'WootEditor',
  props: {
    hiddenMenuOptions: { type: Array, default: () => [] },
    copilotAvailable: { type: Boolean, default: null },
  },
  emits: ['executeCopilotAction'],
  setup:
    (props, { emit }) =>
    () =>
      h('button', {
        'data-editor-falso': '',
        'data-ocultos': props.hiddenMenuOptions.join(','),
        'data-ia': String(props.copilotAvailable),
        onClick: () => emit('executeCopilotAction', 'improve', 'Oi Marina'),
      }),
});

const montar = () =>
  mount(NovaConversaCaixaDoEmail, {
    props: {
      canal: { id: 4, channelType: INBOX_TYPES.EMAIL },
      mensagem: 'Oi Marina',
      'onUpdate:mensagem': vi.fn(),
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        WootEditor: EditorFalso,
        NovaConversaBarraDoEmail: {
          emits: ['update:formatacao'],
          template:
            '<button data-aa-falso @click="$emit(\'update:formatacao\', true)" />',
        },
        CopilotEditorSection: {
          props: ['generatedContent'],
          template: '<div data-sugestao>{{ generatedContent }}</div>',
        },
        CopilotReplyBottomPanel: {
          emits: ['submit', 'cancel'],
          template:
            '<div><button data-aceitar @click="$emit(\'submit\')" /><button data-descartar @click="$emit(\'cancel\')" /></div>',
        },
        AttachmentPreviews: true,
        AvisoDeAssinatura: true,
        CampoDeEnderecos: true,
      },
    },
  });

beforeEach(() => {
  esquecerDisponibilidade();
  estado.alerta.mockReset();
  estado.api.status
    .mockReset()
    .mockResolvedValue({ data: { available: true } });
  estado.api.runText
    .mockReset()
    .mockResolvedValue({ data: { text: 'Olá, Marina!', available: true } });
});

describe('NovaConversaCaixaDoEmail (#1809, #1872)', () => {
  it('o editor do e-mail não mostra o botão de imagem; o ✨ segue a IA do cliente', async () => {
    const wrapper = montar();
    await flushPromises();
    const editor = wrapper.findComponent(EditorFalso);
    expect(editor.props('hiddenMenuOptions')).toEqual(['imageUpload']);
    expect(editor.props('copilotAvailable')).toBe(true);
    expect(editor.attributes('enable-captain-tools')).toBeUndefined();
  });

  it('sem a IA do cliente na conta, o ✨ não aparece', async () => {
    estado.api.status.mockResolvedValue({ data: { available: false } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findComponent(EditorFalso).props('copilotAvailable')).toBe(
      false
    );
  });

  it('o ✨ reescreve só o texto (sem conversa) e Aceitar troca a mensagem', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-editor-falso]').trigger('click');
    await flushPromises();
    expect(estado.api.runText).toHaveBeenCalledWith(
      { task: 'rewrite', draft: 'Oi Marina' },
      expect.objectContaining({ timeoutMs: 90000 })
    );
    expect(wrapper.find('[data-sugestao]').text()).toBe('Olá, Marina!');
    expect(wrapper.find('[data-editor-falso]').exists()).toBe(false);
    await wrapper.find('[data-aceitar]').trigger('click');
    expect(wrapper.emitted('update:mensagem')).toEqual([['Olá, Marina!']]);
    expect(wrapper.find('[data-editor-falso]').exists()).toBe(true);
  });

  it('Descartar volta ao texto como estava', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-editor-falso]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-descartar]').trigger('click');
    expect(wrapper.emitted('update:mensagem')).toBeUndefined();
    expect(wrapper.find('[data-editor-falso]').exists()).toBe(true);
    expect(wrapper.find('[data-aa-falso]').exists()).toBe(true);
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
