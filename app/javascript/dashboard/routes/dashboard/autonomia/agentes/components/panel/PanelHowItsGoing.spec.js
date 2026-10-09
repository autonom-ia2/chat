import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PanelHowItsGoing from './PanelHowItsGoing.vue';

const analytics = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { analytics },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const result = {
  data: {
    range: '7d',
    conversations_handled: 12,
    replies_sent: 20,
    handoff_count: 4,
    handoff_rate: 0.2,
    avg_confidence: 0.8,
    knowledge_answer_rate: 0.7,
    outcomes: {
      handled: 12,
      resolved_without_human: 8,
      handed_off: 4,
      reopened: 1,
      wrong_replies: 2,
    },
    timeline: [{ date: '2026-10-08', replies: 4, handoffs: 1 }],
    top_handoff_reasons: [{ reason: 'low_confidence', count: 4 }],
    insight: null,
  },
};

const mountPanel = (agent = { id: 42, actuation: 'external' }) =>
  mount(PanelHowItsGoing, {
    props: { agent, canManage: true },
    global: {
      stubs: {
        Icon: true,
        Spinner: true,
        PanelConversationsDrawer: true,
      },
      mocks: { $t: key => key },
    },
  });

describe('PanelHowItsGoing', () => {
  beforeEach(() => {
    analytics.mockReset();
    analytics.mockResolvedValue(result);
  });

  it('busca o período por agente e abre os cinco resultados do payload', async () => {
    const wrapper = mountPanel();
    await flushPromises();

    expect(analytics).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ range: '7d' })
    );
    expect(wrapper.find('[data-testid="agent-performance"]').exists()).toBe(
      true
    );
    const summary = wrapper.find('[data-testid="agent-external-summary"]');
    expect(summary.text()).toContain('20%');
    expect(summary.text()).toContain('handed off to the team (4)');
    expect(summary.text()).not.toContain('20% · 4');
    expect(wrapper.text()).toContain('Conversation results');
    expect(wrapper.text()).toContain('Day to day');
    expect(wrapper.text()).toContain('Why conversations went to the team');
    expect(wrapper.findAll('button[data-metric]')).toHaveLength(5);
    expect(wrapper.find('[data-metric="handed_off"]').text()).toContain('4');

    await wrapper
      .findAll('button')
      .find(button => button.text().includes('30'))
      .trigger('click');
    await flushPromises();
    expect(analytics).toHaveBeenCalledTimes(2);
  });

  it('encaixa os 30 dias no desktop e mantém o gráfico rolável no celular', async () => {
    const timeline = Array.from({ length: 30 }, (_, index) => ({
      date: new Date(Date.UTC(2026, 8, 9 + index)).toISOString().slice(0, 10),
      replies: index === 29 ? 54 : 0,
      handoffs: 0,
    }));
    analytics.mockResolvedValue({
      data: { ...result.data, range: '30d', timeline },
    });

    const wrapper = mountPanel();
    await flushPromises();

    const scroller = wrapper.get('[data-timeline-scroll]');
    const timelineElement = wrapper.get('[data-testid="agent-timeline"]');

    expect(timelineElement.classes()).toEqual(
      expect.arrayContaining(['lg:w-full', 'lg:min-w-0'])
    );
    expect(timelineElement.classes()).toContain('min-w-max');
    expect(scroller.attributes('role')).toBe('region');
    expect(scroller.attributes('tabindex')).toBe('0');
    expect(
      wrapper.findAll('[data-testid="agent-timeline"] > div[role="img"]')
    ).toHaveLength(30);
  });

  it('não chama analytics nem exibe números para agente interno', async () => {
    const wrapper = mountPanel({ id: 43, actuation: 'internal' });
    await flushPromises();

    expect(analytics).not.toHaveBeenCalled();
    expect(wrapper.find('[data-state="internal"]').exists()).toBe(true);
    expect(wrapper.find('[data-metric]').exists()).toBe(false);
  });

  it('mostra Ver 30 dias quando a semana está vazia', async () => {
    analytics.mockResolvedValue({
      data: {
        ...result.data,
        conversations_handled: 0,
        replies_sent: 0,
        handoff_count: 0,
        timeline: [{ date: '2026-10-08', replies: 0, handoffs: 0 }],
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.find('[data-state="empty-week"]').exists()).toBe(true);
    expect(wrapper.find('[data-action="show-30-days"]').exists()).toBe(true);
  });

  it('mostra Testar quando os 30 dias também estão vazios', async () => {
    analytics
      .mockResolvedValueOnce({
        data: {
          ...result.data,
          conversations_handled: 0,
          replies_sent: 0,
          handoff_count: 0,
          timeline: [{ date: '2026-10-08', replies: 0, handoffs: 0 }],
        },
      })
      .mockResolvedValueOnce({
        data: {
          ...result.data,
          range: '30d',
          conversations_handled: 0,
          replies_sent: 0,
          handoff_count: 0,
          timeline: [{ date: '2026-10-08', replies: 0, handoffs: 0 }],
        },
      });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.get('[data-action="show-30-days"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-state="empty-total"]').exists()).toBe(true);
    expect(wrapper.find('[data-action="open-test"]').exists()).toBe(true);
  });

  it('mantém a seção de motivos quando nenhuma conversa foi transferida', async () => {
    analytics.mockResolvedValue({
      data: {
        ...result.data,
        top_handoff_reasons: [],
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.find('[data-state="empty-reasons"]').exists()).toBe(true);
    expect(wrapper.find('[data-state="empty-reasons"]').text()).not.toContain(
      'AGENTS.PERFORMANCE.REASONS.EMPTY'
    );
  });
});
