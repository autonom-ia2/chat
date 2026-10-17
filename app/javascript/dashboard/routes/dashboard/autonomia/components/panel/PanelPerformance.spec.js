import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';

// fork chat#1709: the deliberate silences of the AI get their own list, outside the handoff reasons.
const getters = vi.hoisted(() => ({}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name => getters[name],
}));

import PanelPerformance from './PanelPerformance.vue';

withFullI18n();

const payload = (extra = {}) => ({
  agentId: 7,
  range: '7d',
  conversations_handled: 1,
  replies_sent: 1,
  handoff_count: 0,
  handoff_rate: 0,
  avg_confidence: null,
  knowledge_answer_rate: 0,
  top_handoff_reasons: [],
  silences: [],
  outcomes: {},
  timeline: [],
  insight: null,
  ...extra,
});

const mountPanel = analytics => {
  getters['autonomiaAnalytics/getAnalytics'] = ref(analytics);
  getters['autonomiaAnalytics/getUIFlags'] = ref({
    fetching: false,
    error: false,
  });
  return mount(PanelPerformance, {
    props: { agent: { id: 7 } },
    global: {
      stubs: {
        Icon: true,
        Spinner: true,
        NextButton: true,
        PerformanceOutcomes: true,
        PerformanceConversationsPanel: true,
      },
    },
  });
};

describe('PanelPerformance silences', () => {
  it('lists each silence with its label and count, apart from the handoff reasons', () => {
    const wrapper = mountPanel(
      payload({
        silences: [
          { reason: 'mensagem_sem_suporte', count: 3 },
          { reason: 'escolha_retirada', count: 1 },
        ],
      })
    );

    expect(wrapper.text()).toContain('When the AI stayed quiet');
    expect(wrapper.text()).toContain(
      'Message WhatsApp only shows on the phone'
    );
    expect(wrapper.text()).toContain(
      'Vote or reply taken back by the customer'
    );
    expect(wrapper.text()).toContain('No handoffs in this period.');
  });

  it('hides the list when there was no silence', () => {
    expect(mountPanel(payload()).text()).not.toContain(
      'When the AI stayed quiet'
    );
  });

  it('shows the data, not the empty state, when the AI only stayed quiet', () => {
    const wrapper = mountPanel(
      payload({
        replies_sent: 0,
        silences: [{ reason: 'mensagem_apagada', count: 2 }],
      })
    );

    expect(wrapper.text()).toContain('Message deleted by the customer');
  });
});
