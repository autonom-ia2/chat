import { flushPromises, mount } from '@vue/test-utils';
import PanelPublish from './PanelPublish.vue';
import { ativarPedeCanal, publicarNoCanal } from './publicacao';

// #1366 — painel antigo (flag da jornada desligada): conectar e ativar é um passo só no servidor,
// e o botão de status não liga no vazio.
const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => store,
  useMapGetter: () => ({ value: [] }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const router = vi.hoisted(() => ({ replace: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => router }));
vi.mock('../builder/BuilderReview.vue', () => ({
  default: { name: 'BuilderReview', emits: ['connect'], render: () => null },
}));

describe('publicarNoCanal', () => {
  it('connects with ativar, never a status PATCH first', async () => {
    store.dispatch.mockResolvedValue({});
    await publicarNoCanal(store, 7, 3);
    expect(store.dispatch.mock.calls).toEqual([
      ['autonomiaChannels/connect', { agentId: 7, inboxId: 3, ativar: true }],
    ]);
  });
});

describe('ativarPedeCanal', () => {
  it('sends an agent with nowhere to work to the channel choice', () => {
    expect(ativarPedeCanal({ tem_onde_trabalhar: false }, 'active')).toBe(true);
  });

  it('lets the status change through otherwise', () => {
    expect(ativarPedeCanal({ tem_onde_trabalhar: true }, 'active')).toBe(false);
    expect(ativarPedeCanal({ tem_onde_trabalhar: false }, 'paused')).toBe(
      false
    );
  });
});

describe('PanelPublish', () => {
  it('publishes on the chosen inbox with ativar and opens the test tab', async () => {
    store.dispatch.mockResolvedValue({});
    const wrapper = mount(PanelPublish, {
      props: { agent: { id: 7, status: 'paused', enabled: false }, agentId: 7 },
    });
    await flushPromises();
    store.dispatch.mockClear();

    wrapper.findComponent({ name: 'BuilderReview' }).vm.$emit('connect', 3);
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaChannels/connect', {
      agentId: 7,
      inboxId: 3,
      ativar: true,
    });
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaAgents/update',
      expect.anything()
    );
    expect(router.replace).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 7, tab: 'test' },
    });
    wrapper.unmount();
  });
});
