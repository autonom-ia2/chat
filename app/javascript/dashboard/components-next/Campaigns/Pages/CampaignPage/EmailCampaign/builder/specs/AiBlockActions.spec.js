import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { shallowRef } from 'vue';
import en from 'dashboard/i18n/locale/en/campaign.json';

const editor = vi.hoisted(() => ({}));
vi.mock('../composables/useEmailEditor', async () => {
  const { computed } = await import('vue');
  const { isTextComponentType } = await vi.importActual('../editorTextTypes');
  return {
    useEmailEditor: () => ({
      selectedComponent: editor.selected,
      isTextSelected: computed(() =>
        isTextComponentType(editor.selected.value?.get('type'))
      ),
      getSelectedText: () => editor.text,
      setSelectedText: editor.setSelectedText,
    }),
  };
});
const rewrite = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/emailCampaignAi', () => ({ default: { rewrite } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const { default: AiBlockActions } = await import('../AiBlockActions.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const component = type => ({ get: key => (key === 'type' ? type : null) });

const mountActions = type => {
  editor.selected = shallowRef(type ? component(type) : null);
  editor.text = 'Olá, tudo bem?';
  editor.setSelectedText = vi.fn();
  return mount(AiBlockActions, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });
};

const trigger = wrapper => wrapper.find('[data-test="ai-block-trigger"]');
const HINT = 'Click a text or button in the e-mail to improve it with AI.';

// #1093: "Melhorar com IA" only for text and button; a section or column is never replaced.
describe('AiBlockActions', () => {
  it.each(['mj-text', 'mj-button'])(
    'is on, looks on and has no hint for %s',
    type => {
      const wrapper = mountActions(type);

      expect(trigger(wrapper).attributes('disabled')).toBeUndefined();
      expect(trigger(wrapper).classes()).not.toContain('bg-n-slate-9/10');
      expect(trigger(wrapper).classes()).toContain('!min-h-11');
      expect(wrapper.text()).not.toContain(HINT);
    }
  );

  it.each([null, 'mj-section', 'mj-column', 'mj-image', 'mj-wrapper'])(
    'is off with a visible hint when the selection is %s',
    type => {
      const wrapper = mountActions(type);

      expect(trigger(wrapper).attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-test="ai-block-hint"]').text()).toBe(HINT);
    }
  );

  it('rewrites only the selected text block', async () => {
    rewrite.mockResolvedValue({ data: { text: 'Oi! Tudo certo?' } });
    const wrapper = mountActions('mj-text');

    await trigger(wrapper).trigger('click');
    wrapper
      .findComponent({ name: 'DropdownMenu' })
      .vm.$emit('action', { action: 'shorten' });
    await flushPromises();

    expect(rewrite).toHaveBeenCalledWith({
      text: 'Olá, tudo bem?',
      instruction: 'Encurte o texto mantendo a mensagem principal.',
    });
    expect(editor.setSelectedText).toHaveBeenCalledWith('Oi! Tudo certo?');
  });
});
