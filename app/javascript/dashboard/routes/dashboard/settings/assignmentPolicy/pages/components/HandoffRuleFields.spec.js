import { mount } from '@vue/test-utils';
import { defineComponent, reactive } from 'vue';
import HandoffRuleFields from './HandoffRuleFields.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const ChoiceSelectStub = {
  props: ['ariaLabel', 'modelValue', 'options'],
  template:
    '<button type="button" role="combobox" :aria-label="ariaLabel">{{ modelValue }}</button>',
};

const makeForm = overrides => ({
  enabled: false,
  mode: 'round_robin',
  handoff_mode: 'r2_direct',
  trigger: '',
  prefer_online: true,
  pickup_threshold_seconds: 900,
  escalation_user_id: null,
  pool_type: 'inbox',
  pool_id: null,
  escalation_action: 'renotify',
  ...overrides,
});

const mountFields = overrides => {
  const form = reactive(makeForm(overrides));
  const wrapper = mount(
    defineComponent({
      components: { HandoffRuleFields },
      setup: () => ({ form }),
      template:
        '<HandoffRuleFields v-model="form" :agent-options="[{ value: 7, label: \'Maria\' }]" />',
    }),
    { global: { stubs: { ChoiceSelect: ChoiceSelectStub } } }
  );

  return { form, wrapper };
};

const findButton = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

it('keeps the enable control keyboard-sized and reveals the rule fields', async () => {
  const { form, wrapper } = mountFields();
  const enableButton = wrapper.find('button[role="switch"]');

  expect(enableButton.classes()).toContain('min-h-11');
  await enableButton.trigger('click');

  expect(form.enabled).toBe(true);
  expect(wrapper.find('textarea').exists()).toBe(true);
});

it('preserves flow and pickup threshold behavior in the simplified cards', async () => {
  const { form, wrapper } = mountFields({ enabled: true });

  await findButton(wrapper, 'CRM_KANBAN.HANDOFF_SETTINGS.FLOW_INVITE').trigger(
    'click'
  );
  expect(form.handoff_mode).toBe('r3_invite');

  await wrapper.find('input[type="number"]').setValue('7');
  expect(form.pickup_threshold_seconds).toBe(420);
});

it('keeps inbox and specific-person pool choices mutually consistent', async () => {
  const { form, wrapper } = mountFields({
    enabled: true,
    pool_type: 'user',
    pool_id: 7,
  });

  await findButton(wrapper, 'CRM_KANBAN.HANDOFF_SETTINGS.POOL_INBOX').trigger(
    'click'
  );

  expect(form.pool_type).toBe('inbox');
  expect(form.pool_id).toBeNull();
});
