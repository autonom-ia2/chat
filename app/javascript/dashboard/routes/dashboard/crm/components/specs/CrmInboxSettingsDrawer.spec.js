import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import CrmInboxSettingsDrawer from '../CrmInboxSettingsDrawer.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}|${params.count}` : key),
  }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

const INBOXES = [
  { id: 1, name: 'A WhatsApp', channel_type: 'Channel::Whatsapp' },
  { id: 2, name: 'B E-mail', channel_type: 'Channel::Email' },
];

const SETTINGS = [
  { inbox_id: 1, crm_enabled: false, visibility_mode: 'all_inbox_cards' },
  { inbox_id: 2, crm_enabled: false, visibility_mode: 'all_inbox_cards' },
];

const mountDrawer = (props = {}) =>
  mount(CrmInboxSettingsDrawer, {
    props: {
      show: true,
      inboxes: INBOXES,
      settings: SETTINGS,
      pipelines: [{ id: 10, name: 'Funil' }],
      ...props,
    },
    global: {
      stubs: {
        transition: false,
        Spinner: true,
        ComboBox: {
          props: ['modelValue', 'options', 'disabled', 'placeholder'],
          emits: ['update:modelValue'],
          template: '<div class="combobox" />',
        },
        Button: {
          props: ['label', 'isLoading', 'disabled'],
          emits: ['click'],
          template:
            '<button :data-loading="isLoading" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const sections = wrapper => wrapper.findAll('section');
const crmToggle = section => section.find('input[type="checkbox"]');
const saveButton = section =>
  section
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.INBOX_SETTINGS.SAVE');

describe('CrmInboxSettingsDrawer', () => {
  it('uses the design-system choice component, never a native select', () => {
    const wrapper = mountDrawer();
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.findAll('.combobox')).toHaveLength(6);
  });

  it('only enables Save for an inbox that changed', async () => {
    const wrapper = mountDrawer();
    const [first, second] = sections(wrapper);

    expect(saveButton(first).attributes('disabled')).toBeDefined();
    await crmToggle(first).setValue(true);

    expect(saveButton(first).attributes('disabled')).toBeUndefined();
    expect(saveButton(second).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('CRM_KANBAN.INBOX_SETTINGS.UNSAVED|1');
  });

  it('shows Saved on the inbox that was saved and keeps unsaved edits elsewhere', async () => {
    const wrapper = mountDrawer();
    const [first, second] = sections(wrapper);

    await crmToggle(first).setValue(true);
    await crmToggle(second).setValue(true);
    await saveButton(first).trigger('click');

    expect(wrapper.emitted('save')[0][0]).toMatchObject({
      inboxId: 1,
      crm_enabled: true,
    });
    expect(saveButton(first).attributes('data-loading')).toBe('true');
    expect(saveButton(second).attributes('data-loading')).toBe('false');

    await wrapper.setProps({
      settings: [{ ...SETTINGS[0], crm_enabled: true }, SETTINGS[1]],
    });
    await wrapper.setProps({ saveResult: { inboxId: '1', ok: true, at: 1 } });
    await nextTick();

    const [firstAfter, secondAfter] = sections(wrapper);
    expect(firstAfter.text()).toContain('CRM_KANBAN.INBOX_SETTINGS.SAVED');
    expect(crmToggle(secondAfter).element.checked).toBe(true);
    expect(saveButton(secondAfter).attributes('disabled')).toBeUndefined();
  });

  it('keeps the edits and frees the button when saving fails', async () => {
    const wrapper = mountDrawer();
    const [first] = sections(wrapper);

    await crmToggle(first).setValue(true);
    await saveButton(first).trigger('click');
    await wrapper.setProps({ saveResult: { inboxId: 1, ok: false, at: 1 } });

    const [firstAfter] = sections(wrapper);
    expect(firstAfter.text()).not.toContain('CRM_KANBAN.INBOX_SETTINGS.SAVED');
    expect(crmToggle(firstAfter).element.checked).toBe(true);
    expect(saveButton(firstAfter).attributes('data-loading')).toBe('false');
  });

  it('closes from the Done button', async () => {
    const wrapper = mountDrawer();
    const done = wrapper
      .findAll('button')
      .find(button => button.text() === 'CRM_KANBAN.INBOX_SETTINGS.DONE');

    await done.trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
