import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { withFullI18n } from 'test-i18n';

import PanelTune from './PanelTune.vue';

// #1454 — o agente não escolhe mais para quem passa a conversa (a Atribuição decide). Salvar as
// configurações rápidas manda, dentro de `config`, só o limite de confiança.
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  getters: {
    'autonomiaAgents/getUIFlags': { updatingItem: false },
    'autonomiaSources/getUIFlags': { creatingItem: false },
  },
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => []),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/builderImages', () => ({ default: {} }));

withFullI18n();

const stubs = {
  NextButton: {
    props: ['label'],
    template: '<button :data-label="label">{{ label }}</button>',
  },
  Avatar: true,
  Input: true,
  TextArea: true,
  ChoiceSelect: true,
  Switch: true,
  Icon: true,
  Dialog: true,
  BuilderChat: true,
  AgentAudienceForm: true,
  AgentScheduleForm: true,
  AgentBookingForm: true,
};

const AGENT = {
  id: 7,
  name: 'Bia',
  mode: 'guided',
  tone: 'friendly',
  config: {
    handoff_strategy: 'always_ask',
    handoff_target_id: 42,
    confidence_threshold: 0.7,
  },
};

describe('PanelTune', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    store.dispatch.mockResolvedValue({});
  });

  it('saves only the confidence threshold inside config, never the retired handoff keys', async () => {
    const wrapper = mount(PanelTune, {
      props: { agent: AGENT, agentId: 7 },
      global: { stubs },
    });
    await flushPromises();

    await wrapper.find('button[data-label="Save changes"]').trigger('click');
    await flushPromises();

    const update = store.dispatch.mock.calls.find(
      ([action]) => action === 'autonomiaAgents/update'
    );
    expect(update[1].config).toEqual({ confidence_threshold: 0.7 });
  });
});
