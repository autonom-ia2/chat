import { enableAutoUnmount, mount } from '@vue/test-utils';
import { nextTick } from 'vue';

import AgentSwitch from './AgentSwitch.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      if (key === 'AGENTS.V2.list.channel') return values.name;
      if (key === 'AGENTS.V2.list.channelMore') {
        return `${values.name} e mais ${values.more}`;
      }
      if (key === 'AGENTS.V2.list.weekStats') {
        return `${values.replies} respostas · passou ${values.handoffs} para a equipe`;
      }
      if (key === 'AGENTS.V2.status.active') return 'Atendendo';
      if (key === 'AGENTS.V2.status.paused') return 'Pausado';
      if (key === 'AGENTS.V2.actions.toggle') {
        return `${values.status}: ${values.name}`;
      }
      return key;
    },
  }),
}));

const loadComponent = () => import('./AgentRow.vue');

const baseAgent = {
  id: 'clara',
  name: 'Clara',
  avatar_url: null,
  agent_type: 'custom',
  actuation: 'external',
  voice: 'feminina',
  state: { code: 'E5', continuation: 'performance' },
  channels: [
    { inbox_id: 43, name: 'WhatsApp comercial', channel_type: 'whatsapp' },
  ],
  stats: {
    week: { replies: 14, handoffs: 4 },
    month: { replies: 27, handoffs: 6 },
  },
};

const dialogMethods = {
  open: vi.fn(),
  close: vi.fn(),
};

const ConfirmDialogStub = {
  name: 'ConfirmDialog',
  setup(_props, { expose }) {
    expose(dialogMethods);
    return {};
  },
  template: '<div data-test="confirm-dialog" />',
};

const stubs = {
  AgentAvatar: { template: '<span data-test="avatar">avatar</span>' },
  AgentStatusPill: { template: '<span data-test="status">status</span>' },
  AgentSwitch: false,
  ConfirmDialog: ConfirmDialogStub,
};

const mountRow = async (props = {}, options = {}) => {
  const { default: AgentRow } = await loadComponent();
  return mount(AgentRow, {
    props: { agent: baseAgent, canManage: true, ...props },
    global: {
      stubs,
      mocks: { $t: key => key },
      ...options,
    },
    attachTo: document.body,
  });
};

enableAutoUnmount(afterEach);

beforeEach(() => {
  vi.clearAllMocks();
});

describe('AgentRow', () => {
  it('mostra canal e uma única métrica priorizada da projeção externa', async () => {
    const wrapper = await mountRow();

    expect(wrapper.text()).toContain('WhatsApp comercial');
    expect(wrapper.text()).toContain('14');
    expect(wrapper.text()).toContain('4');
    expect(wrapper.text()).not.toContain('30 dias');
    expect(wrapper.text()).not.toContain('27');
    expect(wrapper.find('[role="switch"]').exists()).toBe(true);
    expect(wrapper.findComponent(AgentSwitch).exists()).toBe(true);
  });

  it('destaca o aviso de canal ausente', async () => {
    const wrapper = await mountRow({
      agent: { ...baseAgent, channels: [] },
    });

    expect(wrapper.find('.i-lucide-alert-triangle').exists()).toBe(true);
    expect(wrapper.find('.text-n-amber-11').exists()).toBe(true);
  });

  it('bloqueia continuar e menu enquanto a ação está ocupada', async () => {
    const wrapper = await mountRow({
      busy: true,
      agent: { ...baseAgent, state: { code: 'E1' } },
    });

    expect(wrapper.get('[data-action="continue"]').attributes('disabled')).toBe(
      ''
    );
    expect(wrapper.get('[data-action="more"]').attributes('disabled')).toBe('');
  });

  it('fecha o menu com Escape e devolve o foco ao gatilho', async () => {
    const wrapper = await mountRow({
      agent: { ...baseAgent, state: { code: 'E1' } },
    });
    const trigger = wrapper.get('[data-action="more"]');

    await trigger.trigger('click');
    await wrapper.get('[role="menu"]').trigger('keydown', { key: 'Escape' });

    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
  });

  it('não exibe métricas para o ajudante interno', async () => {
    const wrapper = await mountRow({
      agent: {
        ...baseAgent,
        id: 'interno',
        name: 'Apoio',
        actuation: 'internal',
      },
    });

    expect(wrapper.text()).toContain('AGENTS.V2.list.internalContext');
    expect(wrapper.text()).not.toContain('14');
    expect(wrapper.text()).not.toContain('27');
  });

  it('oferece somente Abrir para quem só pode ver', async () => {
    const wrapper = await mountRow({ canManage: false });

    expect(wrapper.text()).toContain('AGENTS.V2.actions.open');
    expect(wrapper.text()).not.toContain('AGENTS.V2.actions.pause');
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[aria-haspopup="menu"]').exists()).toBe(false);
  });

  it('não transforma um state.code desconhecido em rascunho', async () => {
    await expect(
      mountRow({ agent: { ...baseAgent, state: { code: 'UNKNOWN' } } })
    ).rejects.toThrow(/state\.code/);
  });

  it('confirma a pausa de E5 com o payload de status correto', async () => {
    const wrapper = await mountRow();
    const control = wrapper.get('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('true');
    expect(control.text()).toContain('Atendendo');
    expect(control.text()).not.toContain('Clara');
    expect(control.attributes('aria-label')).toBe('Atendendo: Clara');
    await control.trigger('click');
    await nextTick();

    expect(dialogMethods.open).toHaveBeenCalledTimes(1);
    await wrapper.findComponent(ConfirmDialogStub).vm.$emit('confirm');

    expect(wrapper.emitted('toggleStatus')).toEqual([
      [{ status: 'paused', enabled: false }],
    ]);
  });

  it('religa E6 diretamente com o payload de status correto', async () => {
    const wrapper = await mountRow({
      agent: {
        ...baseAgent,
        state: { code: 'E6', continuation: 'performance' },
      },
    });
    const control = wrapper.get('[role="switch"]');

    expect(control.attributes('aria-checked')).toBe('false');
    expect(control.text()).toContain('Pausado');
    expect(control.text()).not.toContain('Clara');
    expect(control.attributes('aria-label')).toBe('Pausado: Clara');
    await control.trigger('click');

    expect(wrapper.emitted('toggleStatus')).toEqual([
      [{ status: 'active', enabled: true }],
    ]);
    expect(dialogMethods.open).not.toHaveBeenCalled();
  });

  it('bloqueia o interruptor real enquanto a ação está ocupada', async () => {
    const wrapper = await mountRow({ busy: true });
    const control = wrapper.get('[role="switch"]');

    expect(control.attributes('disabled')).toBeDefined();
    await control.trigger('click');

    expect(wrapper.emitted('toggleStatus')).toBeUndefined();
    expect(dialogMethods.open).not.toHaveBeenCalled();
  });
});
