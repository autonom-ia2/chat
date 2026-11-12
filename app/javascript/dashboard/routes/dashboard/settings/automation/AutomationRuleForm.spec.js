import { nextTick, reactive } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AutomationRuleForm from './AutomationRuleForm.vue';
import AutomationRunTypeSelector from './components/AutomationRunTypeSelector.vue';
import AutomationWaitCondition from './components/AutomationWaitCondition.vue';
import AutomationActions from './components/AutomationActions.vue';
import AutomationInstantTrigger from './components/AutomationInstantTrigger.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

// #2414: webhook e transcrição por e-mail só para quem tem integration_manage. #2473: ação e condição de funil só
// para quem tem a chave de funis (crm_manage_pipelines ou crm_admin).
let podeIntegrar = true;
let chavesDeFunil = ['crm_manage_pipelines'];
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    usePermissionGranted: key =>
      computed(() =>
        key === 'integration_manage'
          ? podeIntegrar
          : chavesDeFunil.includes(key)
      ),
  };
});

vi.mock('dashboard/components-next/filter/operators', () => ({
  useOperators: () => ({ operators: { value: {} } }),
}));

// The fork gates CRM automation keys on globalConfig (466a1da717). This spec mounts
// the form without a Vuex store, so only that getter is stubbed (CRM off unless a test turns it on).
let crmLigado = false;
vi.mock('dashboard/composables/store', async importOriginal => {
  const { ref } = await import('vue');
  const original = await importOriginal();
  return {
    ...original,
    useMapGetter: key =>
      key === 'globalConfig/get'
        ? ref({ crmKanbanEnabled: crmLigado })
        : original.useMapGetter(key),
  };
});

const automationTypes = Object.fromEntries(
  [
    'conversation_created',
    'conversation_updated',
    'conversation_resolved',
    'message_created',
    'conversation_opened',
  ].map(event => [event, { conditions: [] }])
);

const triggerStub = {
  props: ['filterTypes'],
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const waitConditionStub = {
  props: ['isSavedWait'],
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const instantConditions = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: 'open',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

const waitConditions = [
  {
    attribute_key: 'message_type',
    filter_operator: 'equal_to',
    values: 'outgoing',
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'private_note',
    filter_operator: 'equal_to',
    values: false,
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'priority',
    filter_operator: 'equal_to',
    values: 'high',
    query_operator: null,
    custom_attribute_type: '',
  },
];

const buildAutomation = ({ delayed = false } = {}) => ({
  name: 'Follow up',
  description: 'Follow up after a wait',
  event_name: delayed ? 'message_created' : 'conversation_created',
  execution_delay: delayed ? 60 : null,
  conditions: structuredClone(delayed ? waitConditions : instantConditions),
  actions: [{ action_name: 'assign_agent', action_params: [] }],
  files: [],
});

const panelOpen = vi.fn();

const mountComponent = ({ mode, automation, types = automationTypes }) =>
  shallowMount(AutomationRuleForm, {
    props: {
      mode,
      automation,
      automationTypes: types,
      getConditionDropdownValues: vi.fn(() => []),
      getActionDropdownValues: vi.fn(() => []),
      appendNewCondition: vi.fn(),
      appendNewAction: vi.fn(),
      removeFilter: vi.fn(),
      removeAction: vi.fn(),
      resetAction: vi.fn(),
      onEventChange: vi.fn(),
    },
    global: {
      stubs: {
        SidePanel: {
          template: '<div><slot /><slot name="footer" /></div>',
          methods: {
            open: panelOpen,
            close: vi.fn(),
          },
        },
        AutomationInstantTrigger: triggerStub,
        AutomationWaitCondition: waitConditionStub,
        WootInput: true,
      },
    },
  });

const selectRunType = async (wrapper, isDelayed) => {
  wrapper
    .findComponent(AutomationRunTypeSelector)
    .vm.$emit('update:modelValue', isDelayed);
  await nextTick();
};

describe('AutomationRuleForm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    podeIntegrar = true;
    chavesDeFunil = ['crm_manage_pipelines'];
    crmLigado = false;
  });

  const actionKeys = wrapper =>
    wrapper
      .findComponent(AutomationActions)
      .props('actionTypes')
      .map(({ key }) => key);

  it('com integration_manage, oferece webhook e transcrição por e-mail', () => {
    const wrapper = mountComponent({
      mode: 'create',
      automation: buildAutomation(),
    });

    expect(actionKeys(wrapper)).toEqual(
      expect.arrayContaining(['send_webhook_event', 'send_email_transcript'])
    );
  });

  it('sem integration_manage, esconde webhook e transcrição por e-mail', () => {
    podeIntegrar = false;
    const wrapper = mountComponent({
      mode: 'create',
      automation: buildAutomation(),
    });

    expect(actionKeys(wrapper)).not.toContain('send_webhook_event');
    expect(actionKeys(wrapper)).not.toContain('send_email_transcript');
    expect(actionKeys(wrapper)).toContain('assign_agent');
  });

  const botaoSalvar = wrapper => wrapper.findAllComponents(NextButton).at(-1);
  const avisoTravada = wrapper => wrapper.find('p.text-n-amber-11');

  it('sem integration_manage, a regra com webhook não salva e diz por quê', () => {
    podeIntegrar = false;
    const automation = buildAutomation();
    automation.actions = [
      { action_name: 'send_webhook_event', action_params: [] },
    ];
    const wrapper = mountComponent({ mode: 'edit', automation });

    expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(true);
    expect(avisoTravada(wrapper).exists()).toBe(true);
  });

  it('sem integration_manage, tirar o webhook da regra também não salva', async () => {
    podeIntegrar = false;
    const automation = buildAutomation();
    automation.actions = [
      { action_name: 'send_webhook_event', action_params: [] },
    ];
    const wrapper = mountComponent({ mode: 'edit', automation });

    automation.actions = [{ action_name: 'assign_agent', action_params: [] }];
    await nextTick();

    expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(true);
  });

  it('sem integration_manage, a regra sem saída para fora salva', () => {
    podeIntegrar = false;
    const wrapper = mountComponent({
      mode: 'create',
      automation: buildAutomation(),
    });

    expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(false);
    expect(avisoTravada(wrapper).exists()).toBe(false);
  });

  it('com integration_manage, a regra com webhook salva', () => {
    const automation = buildAutomation();
    automation.actions = [
      { action_name: 'send_webhook_event', action_params: [] },
    ];
    const wrapper = mountComponent({ mode: 'edit', automation });

    expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(false);
  });

  it('sem integration_manage, a regra que já manda webhook continua mostrando a ação', () => {
    podeIntegrar = false;
    const automation = buildAutomation();
    automation.actions = [
      { action_name: 'send_webhook_event', action_params: [] },
    ];
    const wrapper = mountComponent({ mode: 'edit', automation });

    expect(actionKeys(wrapper)).toContain('send_webhook_event');
    expect(actionKeys(wrapper)).not.toContain('send_email_transcript');
  });

  describe('regra que mexe no funil (#2473)', () => {
    const comCondicoesDeCrm = Object.fromEntries(
      Object.keys(automationTypes).map(event => [
        event,
        {
          conditions: [
            { key: 'status', name: 'STATUS', inputType: 'multi_select' },
            {
              key: 'crm_stage_id',
              name: 'CRM_STAGE',
              inputType: 'multi_select',
            },
          ],
        },
      ])
    );
    const conditionKeys = wrapper =>
      wrapper
        .findComponent(AutomationInstantTrigger)
        .props('filterTypes')
        .map(({ value }) => value);
    const comCrm = () =>
      mountComponent({
        mode: 'create',
        automation: buildAutomation(),
        types: comCondicoesDeCrm,
      });

    beforeEach(() => {
      crmLigado = true;
    });

    it('com a chave de funis, oferece a ação e a condição de funil', () => {
      const wrapper = comCrm();

      expect(actionKeys(wrapper)).toContain('crm_move_card_stage');
      expect(conditionKeys(wrapper)).toContain('crm_stage_id');
    });

    it('com crm_admin no lugar de crm_manage_pipelines, também oferece', () => {
      chavesDeFunil = ['crm_admin'];
      const wrapper = comCrm();

      expect(actionKeys(wrapper)).toContain('crm_create_card');
      expect(conditionKeys(wrapper)).toContain('crm_stage_id');
    });

    it('sem a chave de funis, esconde a ação e a condição de funil, e o resto do CRM continua', () => {
      chavesDeFunil = [];
      const wrapper = comCrm();

      expect(actionKeys(wrapper)).not.toContain('crm_move_card_stage');
      expect(actionKeys(wrapper)).not.toContain('crm_create_card');
      expect(actionKeys(wrapper)).toContain('disable_crm_ai_followup');
      expect(conditionKeys(wrapper)).not.toContain('crm_stage_id');
      expect(conditionKeys(wrapper)).toContain('status');
      expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(false);
      expect(avisoTravada(wrapper).exists()).toBe(false);
    });

    it('sem a chave de funis, a regra que já move card mostra a ação, não salva e diz por quê', () => {
      chavesDeFunil = [];
      const automation = buildAutomation();
      automation.actions = [
        { action_name: 'crm_move_card_stage', action_params: [7] },
      ];
      const wrapper = mountComponent({ mode: 'edit', automation });

      expect(actionKeys(wrapper)).toContain('crm_move_card_stage');
      expect(actionKeys(wrapper)).not.toContain('crm_create_card');
      expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(true);
      expect(avisoTravada(wrapper).text()).toBe(
        'AUTOMATION.RULE_FUNNEL_MANAGE_ONLY'
      );
    });

    it('sem a chave de funis, tirar a condição de funil da regra também não salva', async () => {
      chavesDeFunil = [];
      const automation = buildAutomation();
      automation.conditions = [
        {
          attribute_key: 'crm_stage_id',
          filter_operator: 'equal_to',
          values: [3],
          query_operator: null,
          custom_attribute_type: '',
        },
      ];
      const wrapper = mountComponent({
        mode: 'edit',
        automation,
        types: comCondicoesDeCrm,
      });

      expect(conditionKeys(wrapper)).toContain('crm_stage_id');
      automation.conditions = structuredClone(instantConditions);
      await nextTick();

      expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(true);
    });

    it('com a chave de funis, a regra que move card salva', () => {
      const automation = buildAutomation();
      automation.actions = [
        { action_name: 'crm_move_card_stage', action_params: [7] },
      ];
      const wrapper = mountComponent({ mode: 'edit', automation });

      expect(botaoSalvar(wrapper).vm.$attrs.disabled).toBe(false);
      expect(avisoTravada(wrapper).exists()).toBe(false);
    });
  });

  it('opens a rule whose conditions hold reactive dropdown options', async () => {
    const automation = buildAutomation();
    // Conditions hydrated from store-backed dropdowns (inboxes, agents, contacts) hold
    // reactive option objects rather than plain ones.
    automation.conditions[0].values = [reactive({ id: 1, name: 'Sales' })];
    const wrapper = mountComponent({ mode: 'edit', automation });

    wrapper.vm.open();
    await nextTick();

    expect(panelOpen).toHaveBeenCalled();
  });

  it('restores unsaved wait conditions after switching a new rule to instant and back', async () => {
    const automation = buildAutomation();
    const wrapper = mountComponent({ mode: 'create', automation });
    wrapper.vm.open();
    await nextTick();

    await selectRunType(wrapper, true);
    automation.event_name = 'message_created';
    automation.conditions = structuredClone(waitConditions);

    await selectRunType(wrapper, false);
    expect(automation.event_name).toBe('conversation_created');
    expect(automation.conditions).toEqual(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });

  it('restores saved wait conditions after editing the instant draft', async () => {
    const automation = buildAutomation({ delayed: true });
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60);
    await nextTick();

    await selectRunType(wrapper, false);
    automation.event_name = 'conversation_created';
    automation.conditions = structuredClone(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });
});
