import { nextTick } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import MessageActionDialogs from '../MessageActionDialogs.vue';
import WahaMessageActionsApi from 'dashboard/api/wahaMessageActions';

vi.mock('dashboard/api/wahaMessageActions', () => ({
  default: {
    react: vi.fn(() => Promise.resolve()),
    edit: vi.fn(() => Promise.resolve()),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

// O diálogo nativo do navegador não existe no jsdom: o Dialog só precisa abrir o conteúdo.
const DialogStub = {
  props: ['title', 'disableConfirmButton'],
  emits: ['confirm', 'close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template:
    '<div v-if="isOpen" data-dialog><slot /><button data-confirm :disabled="disableConfirmButton" @click="$emit(\'confirm\')" /></div>',
};

const montar = (props = {}) =>
  mount(MessageActionDialogs, {
    props: {
      conversationId: 3,
      messageId: 41,
      content: 'Até amanhã',
      reactions: [{ emoji: '👍', by: 'agent', userId: 7 }],
      currentUserId: 7,
      ...props,
    },
    global: {
      stubs: {
        Dialog: DialogStub,
        EmojiPicker: true,
        TextArea: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<textarea :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

describe('diálogos de reagir e editar', () => {
  beforeEach(() => vi.clearAllMocks());

  it('reage com um emoji rápido e tira a reação do atendente', async () => {
    const wrapper = montar();
    wrapper.vm.openReaction();
    await nextTick();

    const botoes = wrapper.findAll('[data-quick-reactions] button');
    expect(botoes[0].attributes('aria-pressed')).toBe('true');
    await botoes[1].trigger('click');
    await flushPromises();
    expect(WahaMessageActionsApi.react).toHaveBeenCalledWith(3, 41, '❤️');

    wrapper.vm.openReaction();
    await nextTick();
    const tirar = wrapper
      .findAll('button')
      .find(button => button.text() === 'Tirar minha reação');
    await tirar.trigger('click');
    await flushPromises();
    expect(WahaMessageActionsApi.react).toHaveBeenLastCalledWith(3, 41, '');
  });

  it('edita o texto e só deixa salvar texto novo', async () => {
    const wrapper = montar();
    await wrapper.vm.openEdit();
    await nextTick();

    expect(wrapper.find('[data-confirm]').attributes('disabled')).toBeDefined();
    await wrapper.find('textarea').setValue('Até depois');
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(WahaMessageActionsApi.edit).toHaveBeenCalledWith(
      3,
      41,
      'Até depois'
    );
  });
});
