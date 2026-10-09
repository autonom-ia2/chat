import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import PanelAgentTest from './PanelAgentTest.vue';

const phoneStub = {
  name: 'AgentTestPhone',
  props: [
    'agentId',
    'agent',
    'messages',
    'isTesting',
    'rateLimited',
    'delayed',
    'isInternal',
    'canManage',
    'error',
  ],
  emits: ['test', 'clear', 'teach'],
  template: `
    <div data-testid="agent-panel-test-phone-stub">
      <button type="button" data-action="phone-test" @click="$emit('test', { message: 'Oi', history: [], images: [] })">test</button>
      <button type="button" data-action="phone-retry" @click="$emit('test', { message: 'Oi', history: messages.map(message => ({ role: message.role, content: message.content })), images: [] })">retry</button>
      <button type="button" data-action="phone-clear" @click="$emit('clear')">clear</button>
      <button type="button" data-action="phone-teach" @click="$emit('teach')">teach</button>
      <span data-testid="phone-message-count">{{ messages.length }}</span>
      <span data-testid="phone-error">{{ error || '' }}</span>
      <span v-if="messages.some(message => message.handoff && message.handoff.should)" data-state="handoff" />
    </div>
  `,
};

const { requests } = vi.hoisted(() => ({ requests: [] }));
vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { test: vi.fn() },
}));

withFullI18n('pt_BR');
enableAutoUnmount(afterEach);

const agent = {
  id: 42,
  name: 'Clara',
  type: 'support',
  actuation: 'external',
  has_instruction: true,
};

const mountPanel = (props = {}) =>
  mount(PanelAgentTest, {
    props: { agentId: 42, agent, canManage: true, ...props },
    global: { stubs: { AgentTestPhone: phoneStub } },
  });

const answer = (overrides = {}) => ({
  reply: 'Olá, posso ajudar.',
  confidence: 0.2,
  handoff: { should: false },
  used_knowledge: [{ source: 'Manual' }],
  ...overrides,
});

describe('PanelAgentTest', () => {
  beforeEach(() => {
    requests.length = 0;
    AutonomiaAgentsAPI.test.mockReset();
    AutonomiaAgentsAPI.test.mockImplementation(
      (_agentId, _payload, options) => {
        requests.push(options?.signal);
        return Promise.resolve({ data: answer() });
      }
    );
  });

  it('envia a pergunta pelo endpoint oficial com AbortSignal e mostra a resposta real', async () => {
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await flushPromises();

    expect(AutonomiaAgentsAPI.test).toHaveBeenCalledWith(
      42,
      { message: 'Oi', history: [], images: [] },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('2');
    expect(wrapper.get('[data-testid="agent-panel-test"]')).toBeTruthy();
    expect(wrapper.find('[data-state="handoff"]').exists()).toBe(false);
  });

  it('não deduz passagem pela certeza quando o backend não a devolve', async () => {
    AutonomiaAgentsAPI.test.mockResolvedValueOnce({
      data: answer({ confidence: 0.1, handoff: null }),
    });
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-state="handoff"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('2');
  });

  it('mostra erro seguro quando o backend não entrega resposta', async () => {
    AutonomiaAgentsAPI.test.mockResolvedValueOnce({
      data: answer({ reply: null, error: 'ai_unavailable' }),
    });
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-testid="phone-error"]').text()).toContain(
      'não conseguiu responder'
    );
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('1');
  });

  it('aborta e invalida resposta atrasada ao limpar, trocar de agente e desmontar', async () => {
    let resolveRequest;
    AutonomiaAgentsAPI.test.mockImplementationOnce((_id, _payload, options) => {
      requests.push(options.signal);
      return new Promise(resolve => {
        resolveRequest = resolve;
      });
    });
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await wrapper.get('[data-action="phone-clear"]').trigger('click');
    expect(requests[0].aborted).toBe(true);
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('0');

    await wrapper.setProps({ agentId: 43, agent: { ...agent, id: 43 } });
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('0');

    resolveRequest({ data: answer({ reply: 'Resposta antiga.' }) });
    await flushPromises();
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('0');

    wrapper.unmount();
    expect(requests[0].aborted).toBe(true);
  });

  it('aborta requisição quando desmonta antes do polling terminar', async () => {
    let resolveRequest;
    AutonomiaAgentsAPI.test.mockImplementationOnce((_id, _payload, options) => {
      requests.push(options.signal);
      return new Promise(resolve => {
        resolveRequest = resolve;
      });
    });
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    wrapper.unmount();
    expect(requests[0].aborted).toBe(true);

    resolveRequest({ data: answer() });
    await flushPromises();
  });

  it('mostra demora em 180 segundos, continua aguardando e não duplica a pergunta no retry', async () => {
    vi.useFakeTimers();
    const resolvers = [];
    AutonomiaAgentsAPI.test.mockImplementation((_id, _payload, options) => {
      requests.push(options.signal);
      return new Promise(resolve => {
        resolvers.push(resolve);
      });
    });
    const wrapper = mountPanel();

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('1');

    await vi.advanceTimersByTimeAsync(180 * 1000);
    await flushPromises();
    expect(wrapper.getComponent(phoneStub).props('delayed')).toBe(true);
    expect(requests).toHaveLength(1);

    await wrapper.get('[data-action="phone-retry"]').trigger('click');
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('1');
    expect(requests).toHaveLength(2);

    resolvers[1]({ data: answer() });
    await flushPromises();
    expect(wrapper.get('[data-testid="phone-message-count"]').text()).toBe('2');
    vi.useRealTimers();
  });

  it('expõe estado de montagem e erros de limite sem liberar ação de escrita', async () => {
    const wrapper = mountPanel({
      agent: { ...agent, has_instruction: false },
      canManage: false,
    });

    expect(wrapper.find('[data-state="assembling"]').exists()).toBe(true);
    expect(wrapper.getComponent(phoneStub).props('canManage')).toBe(false);

    AutonomiaAgentsAPI.test.mockRejectedValueOnce({
      response: { status: 429 },
    });
    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-state="rate-limited"]').exists()).toBe(true);
    expect(wrapper.getComponent(phoneStub).props('error')).toBe(null);
  });

  it('permite testar para quem só vê e encaminha ensinar apenas por evento', async () => {
    const wrapper = mountPanel({ canManage: false });

    await wrapper.get('[data-action="phone-test"]').trigger('click');
    await flushPromises();
    expect(AutonomiaAgentsAPI.test).toHaveBeenCalled();

    expect(wrapper.getComponent(phoneStub).props('canManage')).toBe(false);
    await wrapper.get('[data-action="phone-teach"]').trigger('click');
    expect(wrapper.emitted('teach')).toBeUndefined();
  });
});
