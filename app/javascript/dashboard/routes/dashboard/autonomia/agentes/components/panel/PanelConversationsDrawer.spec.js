import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PanelConversationsDrawer from './PanelConversationsDrawer.vue';

const analyticsConversations = vi.hoisted(() => vi.fn());
const routerPush = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { analyticsConversations },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
  useRouter: () => ({ push: routerPush }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const mountDrawer = (props = {}) =>
  mount(PanelConversationsDrawer, {
    props: { agentId: 42, metric: null, ...props },
    global: {
      stubs: {
        SidePanel: {
          setup(_props, { expose }) {
            expose({ open: vi.fn(), close: vi.fn() });
            return {};
          },
          template: '<div data-side-panel><slot /></div>',
        },
        Spinner: true,
        ReportDrilldownCard: {
          props: { record: Object, agentPanel: Boolean },
          template:
            '<article data-record :data-agent-panel="agentPanel">{{ record.message?.content || record.conversation.id }}</article>',
        },
      },
      mocks: { $t: key => key },
    },
  });

describe('PanelConversationsDrawer', () => {
  beforeEach(() => {
    analyticsConversations.mockReset();
    routerPush.mockReset();
    analyticsConversations.mockResolvedValue({
      data: {
        meta: { count: 1, limit: 50, has_more: false, has_hidden: true },
        payload: [{ record_type: 'conversation', conversation: { id: 9 } }],
      },
    });
  });

  it('usa o envelope do drilldown e informa conversas ocultas', async () => {
    const wrapper = mountDrawer();
    await wrapper.setProps({ metric: 'handled' });
    await flushPromises();

    expect(analyticsConversations).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ metric: 'handled', range: '7d' })
    );
    expect(wrapper.find('[data-state="hidden-records"]').exists()).toBe(true);
    expect(wrapper.find('[data-record]').text()).toBe('9');
    expect(wrapper.find('[data-record]').attributes('data-agent-panel')).toBe(
      'true'
    );
  });

  it('cancela a busca quando a métrica é fechada', async () => {
    const wrapper = mountDrawer();
    await flushPromises();
    await wrapper.setProps({ metric: null });
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it('mantém o aviso de ocultas mesmo quando o resultado está vazio', async () => {
    analyticsConversations.mockResolvedValueOnce({
      data: {
        meta: { count: 0, limit: 50, has_more: false, has_hidden: true },
        payload: [],
      },
    });
    const wrapper = mountDrawer();
    await wrapper.setProps({ metric: 'handled' });
    await flushPromises();

    expect(wrapper.find('[data-state="hidden-records"]').exists()).toBe(true);
    expect(wrapper.find('[data-state="empty"]').exists()).toBe(true);
  });

  it('adapta a resposta errada flat e encaminha Ensinar para O que sabe', async () => {
    analyticsConversations.mockResolvedValueOnce({
      data: {
        meta: { count: 1, limit: 50, has_more: false, has_hidden: false },
        payload: [
          {
            report_id: 17,
            message_id: 31,
            message: 'Resposta incorreta',
            suggested_answer: 'Resposta certa',
            conversation_id: 9,
            conversation: { id: 9, display_id: 77 },
          },
        ],
      },
    });
    const wrapper = mountDrawer({ canManage: true });
    await wrapper.setProps({ metric: 'wrong_replies' });
    await flushPromises();

    expect(wrapper.find('[data-record]').text()).toContain(
      'Resposta incorreta'
    );
    expect(
      wrapper.get('[data-testid="agent-conversation-open"]').text()
    ).toContain('Open conversation');
    await wrapper.get('[data-testid="agent-wrong-teach"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 42, tab: 'knowledge' },
    });
  });
});
