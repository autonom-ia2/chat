import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ChannelsAPI from 'dashboard/api/autonomia/channels';
import PanelWhereServes from './PanelWhereServes.vue';

const { inboxManage, push } = vi.hoisted(() => ({
  inboxManage: { value: true },
  push: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/channels', () => ({
  default: { get: vi.fn(), connect: vi.fn(), disconnect: vi.fn() },
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(inboxManage.value),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(7) }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const agent = {
  id: 42,
  name: 'Clara',
  actuation: 'external',
  state: { code: 'E5' },
};
const channels = {
  payload: [
    { id: 11, inbox_id: 1, inbox_name: 'WhatsApp 1', channel_type: 'whatsapp' },
    { id: 12, inbox_id: 2, inbox_name: 'Site 2', channel_type: 'website' },
  ],
  eligible_inboxes: [{ id: 3, name: 'Email 3', channel_type: 'email' }],
  occupied_inboxes: [
    {
      id: 1,
      name: 'WhatsApp 1',
      occupied_by: { kind: 'agent', agent_name: 'Clara' },
    },
    {
      id: 4,
      name: 'Canal 4',
      occupied_by: { kind: 'agent', agent_name: 'Outro agente' },
    },
    { id: 5, name: 'Canal 5', occupied_by: { kind: 'other_bot' } },
  ],
};

const mountPanel = (props = {}) =>
  mount(PanelWhereServes, {
    props: { agentId: 42, agent, canManage: true, ...props },
    global: {
      stubs: {
        ConfirmDialog: {
          name: 'ConfirmDialog',
          props: ['description'],
          setup(_, { expose }) {
            expose({ open: vi.fn(), close: vi.fn() });
          },
          template: '<div data-confirm>{{ description }}</div>',
        },
      },
    },
  });

beforeEach(() => {
  vi.clearAllMocks();
  inboxManage.value = true;
  ChannelsAPI.get.mockResolvedValue({ data: channels });
  ChannelsAPI.connect.mockResolvedValue({ status: 201 });
  ChannelsAPI.disconnect.mockResolvedValue({ status: 204 });
});

describe('PanelWhereServes', () => {
  it('mostra várias caixas atuais e exclui a própria caixa dos ocupados', async () => {
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.findAll('[data-connected-channel]')).toHaveLength(2);
    expect(wrapper.findAll('[data-occupied-channel]')).toHaveLength(2);
    expect(wrapper.text()).toContain('Outro agente');
    expect(ChannelsAPI.get).toHaveBeenCalledWith(42, {
      signal: expect.any(AbortSignal),
    });
  });

  it.each(['E1', 'E3', 'E4', 'E6'])(
    'não coloca em outra caixa no estado %s',
    async code => {
      const wrapper = mountPanel({ agent: { ...agent, state: { code } } });
      await flushPromises();

      expect(
        wrapper.get('[data-action="channel-connect"]').attributes('disabled')
      ).toBeDefined();
      await wrapper.get('[data-action="channel-connect"]').trigger('click');
      expect(ChannelsAPI.connect).not.toHaveBeenCalled();
      expect(wrapper.find('[data-state="channel-inactive"]').exists()).toBe(
        true
      );
    }
  );

  it('mantém os canais até o POST concluir e bloqueia clique duplo', async () => {
    let resolveConnect;
    ChannelsAPI.connect.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveConnect = resolve;
        })
    );
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.get('[data-action="channel-connect"]').trigger('click');
    await wrapper.get('[data-action="channel-connect"]').trigger('click');

    expect(ChannelsAPI.connect).toHaveBeenCalledTimes(1);
    expect(ChannelsAPI.connect).toHaveBeenCalledWith(42, 3);
    expect(ChannelsAPI.get).toHaveBeenCalledTimes(1);
    resolveConnect({ status: 201 });
    await flushPromises();
    expect(ChannelsAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('só remove após confirmação e explica a devolução para a equipe', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.findAll('[data-action="channel-remove"]')[0].trigger('click');

    expect(ChannelsAPI.disconnect).not.toHaveBeenCalled();
    const dialog = wrapper.findComponent({ name: 'ConfirmDialog' });
    expect(dialog.props('description')).toContain('WhatsApp 1');
    dialog.vm.$emit('confirm');
    await flushPromises();
    expect(ChannelsAPI.disconnect).toHaveBeenCalledWith(42, 1);
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('mostra erro específico sem alterar a projeção anterior', async () => {
    ChannelsAPI.connect.mockRejectedValue({
      response: {
        status: 422,
        data: {
          code: 'inbox_already_connected',
          error: 'Canal ocupado pelo servidor.',
        },
      },
    });
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.get('[data-action="channel-connect"]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Canal ocupado pelo servidor.'
    );
    expect(wrapper.findAll('[data-connected-channel]')).toHaveLength(2);
    expect(wrapper.emitted('changed')).toBeUndefined();
  });

  it('oferece tentar de novo após falha de leitura', async () => {
    ChannelsAPI.get.mockRejectedValueOnce(new Error('network'));
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.find('[data-state="channel-load-error"]').exists()).toBe(
      true
    );
    await wrapper.get('[data-action="channels-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-connected-channel]')).toHaveLength(2);
  });

  it('atalha para Canais somente com a permissão própria', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.get('[data-action="open-channels"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'settings_inbox_new',
      params: { accountId: 7 },
    });

    inboxManage.value = false;
    const restricted = mountPanel();
    await flushPromises();
    expect(restricted.find('[data-action="open-channels"]').exists()).toBe(
      false
    );
  });

  it('não lê canais do ajudante interno', async () => {
    mountPanel({ agent: { ...agent, actuation: 'internal' } });
    await flushPromises();
    expect(ChannelsAPI.get).not.toHaveBeenCalled();
  });

  it('ignora leitura atrasada após trocar de agente', async () => {
    let resolveOld;
    ChannelsAPI.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mountPanel();
    await wrapper.setProps({ agentId: 43, agent: { ...agent, id: 43 } });
    await flushPromises();
    resolveOld({
      data: {
        payload: [{ inbox_id: 9, inbox_name: 'Caixa antiga' }],
        eligible_inboxes: [],
        occupied_inboxes: [],
      },
    });
    await flushPromises();

    expect(wrapper.text()).not.toContain('Caixa antiga');
    expect(wrapper.text()).toContain('WhatsApp 1');
  });
});
