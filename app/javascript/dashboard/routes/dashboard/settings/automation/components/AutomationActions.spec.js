import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import AutomationActions from './AutomationActions.vue';
import AutomationLockedAction from './AutomationLockedAction.vue';
import AutomationActionInput from 'dashboard/components/widgets/AutomationActionInput.vue';
import { generateAutomationPayload } from 'dashboard/helper/automationHelper';

// #2413 — a regra do Guia com passo do Decisor quebrava o modo manual: o
// formulário não oferece esse passo e lia `.inputType` de undefined.
const actionTypes = [
  { key: 'add_label', label: 'Add label', inputType: 'multi_select' },
];

const decisor = {
  action_name: 'perguntar_ao_decisor',
  action_params: [12, 'sim'],
};

const mountActions = (actions, removeAction = vi.fn()) =>
  shallowMount(AutomationActions, {
    props: {
      modelValue: actions,
      actionTypes,
      getActionDropdownValues: () => [],
      appendNewAction: vi.fn(),
      removeAction,
      resetAction: vi.fn(),
    },
    global: { mocks: { $t: key => key } },
  });

describe('AutomationActions', () => {
  it('shows a step the form does not offer as locked, without breaking', () => {
    const wrapper = mountActions([
      { action_name: 'add_label', action_params: [] },
      decisor,
    ]);

    const locked = wrapper.findAllComponents(AutomationLockedAction);
    expect(locked).toHaveLength(1);
    expect(locked[0].props('actionName')).toBe('perguntar_ao_decisor');
    expect(wrapper.findAllComponents(AutomationActionInput)).toHaveLength(1);
  });

  it('removes the locked step at its own position', () => {
    const removeAction = vi.fn();
    const wrapper = mountActions(
      [{ action_name: 'add_label', action_params: [] }, decisor],
      removeAction
    );

    wrapper.findComponent(AutomationLockedAction).vm.$emit('removeAction');

    expect(removeAction).toHaveBeenCalledWith(1);
  });

  it('sends the locked step with the same params in the save payload', () => {
    const payload = generateAutomationPayload({
      name: 'Regra',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
        },
      ],
      actions: [{ action_name: 'add_label', action_params: ['lead'] }, decisor],
    });

    expect(payload.actions[1]).toEqual(decisor);
  });
});
