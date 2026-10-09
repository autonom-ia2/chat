import { defineComponent, h } from 'vue';
import { shallowMount } from '@vue/test-utils';
import Message from '../Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES, SENDER_TYPES } from '../constants';

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => ({
    value: key === 'globalConfig/isOnChatwootCloud' ? false : () => ({}),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: text => text,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
}));

vi.mock('dashboard/components-next/CampaignJourney/useCampaignNames', () => ({
  campaignRefFor: () => null,
}));

const ContextMenuStub = defineComponent({
  name: 'ContextMenu',
  props: {
    enabledOptions: { type: Object, required: true },
  },
  setup(props) {
    return () =>
      h('div', {
        'data-test': 'message-context-menu',
        'data-report-agent': props.enabledOptions.reportAgent,
      });
  },
});

const messageProps = {
  id: 1,
  messageType: MESSAGE_TYPES.OUTGOING,
  status: MESSAGE_STATUS.SENT,
  content: 'Resposta do agente',
  contentAttributes: { autonomiaAgentId: 42 },
  conversationId: 7,
  createdAt: 1_723_456_789,
  currentUserId: 9,
  sender: { id: 11, type: SENDER_TYPES.AGENT_BOT, name: 'Ana' },
};

const mountMessage = (props = {}) =>
  shallowMount(Message, {
    props: { ...messageProps, ...props },
    global: {
      stubs: {
        ContextMenu: ContextMenuStub,
      },
    },
  });

describe('Message Autonomia wrong-reply action', () => {
  it('does not expose reportAgent for a private note', () => {
    const wrapper = mountMessage({ private: true });
    const contextMenu = wrapper.findComponent(ContextMenuStub);

    expect(contextMenu.props('enabledOptions').reportAgent).toBe(false);
  });

  it('keeps reportAgent for a public Autonomia reply', () => {
    const wrapper = mountMessage();
    const contextMenu = wrapper.findComponent(ContextMenuStub);

    expect(contextMenu.props('enabledOptions').reportAgent).toBe(true);
  });
});
