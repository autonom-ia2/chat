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

    expect(wrapper.emitted('submit')).toEqual([[null]]);
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

    expect(wrapper.emitted('submit')).toEqual([[audience]]);
  });
});
