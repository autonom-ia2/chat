import { ref } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useOfferedActionTypes } from './useOfferedActionTypes';
import { useEditableAutomation } from 'dashboard/composables/useEditableAutomation';
import { validateActions } from 'dashboard/helper/validations';

const flags = { crm: false, sla: false };

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: flag => flags[flag] === true }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    key === 'globalConfig/get' ? ref({ crmKanbanEnabled: flags.crm }) : ref([]),
}));

// The CRM dropdowns are empty while the CRM is off; that is what used to empty the step.
vi.mock('dashboard/composables/useAutomationValues', () => ({
  default: () => ({
    getConditionDropdownValues: () => [],
    getActionDropdownValues: () => [],
  }),
}));

const keys = () =>
  useOfferedActionTypes().offeredActionTypes.value.map(({ key }) => key);

describe('useOfferedActionTypes', () => {
  beforeEach(() => {
    flags.crm = false;
    flags.sla = false;
  });

  it('leaves out CRM and SLA actions while they are off', () => {
    expect(keys()).not.toContain('crm_move_card_stage');
    expect(keys()).not.toContain('add_sla');
    expect(keys()).toContain('add_label');
  });

  it('offers them once they are on', () => {
    flags.crm = true;
    flags.sla = true;

    expect(keys()).toContain('crm_move_card_stage');
    expect(keys()).toContain('add_sla');
  });

  // #2413 — com o CRM desligado, o passo de CRM salvo não podia virar [] na reidratação:
  // o formulário barrava a regra inteira e a frase "continua na regra" ficava falsa.
  it('keeps the raw params of a step the form does not offer, so the rule still saves', () => {
    const { formatAutomation } = useEditableAutomation();
    const rule = {
      event_name: 'conversation_created',
      conditions: [],
      actions: [{ action_name: 'crm_move_card_stage', action_params: [7] }],
    };

    const formatted = formatAutomation(
      rule,
      [],
      {},
      useOfferedActionTypes().offeredActionTypes.value
    );

    expect(formatted.actions[0].action_params).toEqual([7]);
    expect(validateActions(formatted.actions)).toEqual({});
  });
});
