import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { withFullI18n } from 'test-i18n';

import AgentAudienceForm from './AgentAudienceForm.vue';

withFullI18n();

// The picker needs the contacts filter context (store-backed); stub it with a
// fixed email filter type so hydration/serialization can be exercised.
vi.mock('./audience/useAgentAudienceFilterTypes.js', () => ({
  useAgentAudienceFilterTypes: () => ({
    filterTypes: {
      value: [
        {
          attributeKey: 'email',
          inputType: 'plainText',
          attributeModel: 'standard',
        },
      ],
    },
  }),
}));

const stubs = {
  RadioCard: {
    props: ['id', 'label', 'isActive'],
    template:
      '<div :data-id="id" :data-active="isActive"><button class="pick" @click="$emit(\'select\', id)">{{ label }}</button><slot /></div>',
  },
  // The group only needs to validate and expose the tree it received.
  AgentAudienceGroup: {
    props: ['modelValue'],
    template:
      '<div class="group" :data-count="modelValue.conditions.length" />',
    methods: { validate: () => true },
  },
  NextButton: {
    props: ['label'],
    template: '<button class="save">{{ label }}</button>',
  },
  ChoiceSelect: {
    name: 'ChoiceSelect',
    props: ['modelValue', 'options', 'ariaLabel'],
    emits: ['update:modelValue', 'change'],
    template:
      '<div data-test="choice-select"><button type="button" role="combobox" :aria-label="ariaLabel" :data-value="String(modelValue)">{{ modelValue }}</button><div role="listbox"><button v-for="option in options" :key="option.value" type="button" role="option" :data-value="String(option.value)" @click="$emit(\'update:modelValue\', option.value); $emit(\'change\', option.value)">{{ option.label }}</button></div></div>',
  },
};

const emailLeaf = {
  attribute_key: 'email',
  filter_operator: 'contains',
  values: ['acme'],
};

const mountForm = agent =>
  mount(AgentAudienceForm, { props: { agent }, global: { stubs } });

describe('AgentAudienceForm', () => {
  it('starts on "everyone" when no audience is saved and submits null', async () => {
    const wrapper = mountForm({ config: {} });

    expect(wrapper.find('[data-id="everyone"]').attributes('data-active')).toBe(
      'true'
    );
    await wrapper.find('button.save').trigger('click');

    expect(wrapper.emitted('submit')).toEqual([
      [{ audience: null, audienceUnknownContact: 'respond' }],
    ]);
  });

  it('refuses a specific audience without conditions', async () => {
    const wrapper = mountForm({ config: {} });

    await wrapper.find('[data-id="specific"] button.pick').trigger('click');
    await wrapper.find('button.save').trigger('click');
    await nextTick();

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'Add at least one condition for a specific audience.'
    );
  });

  it('hydrates a saved tree and serializes it back on save', async () => {
    const audience = { operator: 'or', conditions: [emailLeaf] };
    const wrapper = mountForm({ config: { audience } });

    expect(wrapper.find('[data-id="specific"]').attributes('data-active')).toBe(
      'true'
    );
    expect(wrapper.find('.group').attributes('data-count')).toBe('1');

    await wrapper.find('button.save').trigger('click');

    expect(wrapper.emitted('submit')).toEqual([
      [{ audience, audienceUnknownContact: 'respond' }],
    ]);
  });

  describe('conversation without an identified contact', () => {
    const audience = { operator: 'and', conditions: [emailLeaf] };

    it('shows the selector once there is at least one condition', () => {
      const wrapper = mountForm({ config: { audience } });

      expect(wrapper.find('[role="combobox"]').exists()).toBe(true);
      expect(wrapper.text()).toContain(
        'Conversation without an identified contact'
      );
    });

    it('hides the selector for everyone and for a specific audience with no conditions', async () => {
      const wrapper = mountForm({ config: {} });

      expect(wrapper.find('[role="combobox"]').exists()).toBe(false);

      await wrapper.find('[data-id="specific"] button.pick').trigger('click');

      expect(wrapper.find('[role="combobox"]').exists()).toBe(false);
    });

    it('hydrates the saved policy and emits the chosen one with the audience', async () => {
      const wrapper = mountForm({
        config: { audience, audience_unknown_contact: 'handoff' },
      });

      expect(wrapper.find('[role="combobox"]').attributes('data-value')).toBe(
        'handoff'
      );

      await wrapper
        .find('[role="option"][data-value="respond"]')
        .trigger('click');
      await wrapper.find('button.save').trigger('click');

      expect(wrapper.emitted('submit')).toEqual([
        [{ audience, audienceUnknownContact: 'respond' }],
      ]);
    });
  });

  it('preserves a specific-audience draft during an unrelated agent refresh', async () => {
    const wrapper = mountForm({ config: {} });

    await wrapper.find('[data-id="specific"] button.pick').trigger('click');
    await wrapper.setProps({
      agent: { config: { response_window: 'business_hours' } },
    });

    expect(wrapper.find('[data-id="specific"]').attributes('data-active')).toBe(
      'true'
    );
  });

  it('rehydrates the audience policy when its own config changes', async () => {
    const audience = { operator: 'and', conditions: [emailLeaf] };
    const wrapper = mountForm({
      config: { audience, audience_unknown_contact: 'respond' },
    });

    await wrapper.setProps({
      agent: { config: { audience, audience_unknown_contact: 'handoff' } },
    });

    expect(wrapper.find('[role="combobox"]').attributes('data-value')).toBe(
      'handoff'
    );
  });
});
