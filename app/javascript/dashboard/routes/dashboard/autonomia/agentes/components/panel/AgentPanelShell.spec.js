import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgentPanelShell from './AgentPanelShell.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ installationName: { value: 'Hub2You' } }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const agent = {
  id: 42,
  name: 'Clara',
  human_card: 'Ajuda clientes com dúvidas de suporte.',
  state: { code: 'E5' },
  status: 'active',
  enabled: true,
};

const mountShell = (props = {}) =>
  mount(AgentPanelShell, {
    props: {
      agent,
      activeTab: 'performance',
      visibleTabs: [
        'performance',
        'test',
        'knowledge',
        'channels',
        'tune',
        'tools',
      ],
      canManage: true,
      ...props,
    },
    global: {
      stubs: {
        Avatar: { template: '<span data-avatar />' },
        AgentStatusPill: { template: '<span data-status />' },
        'router-link': {
          props: ['to'],
          template:
            '<a data-router-link :data-route-name="to && to.name" :data-account-id="to && to.params && to.params.accountId"><slot /></a>',
        },
      },
      mocks: { $t: key => key },
    },
    attachTo: document.body,
  });

describe('AgentPanelShell', () => {
  it('mantém a ordem normativa das abas e o contrato ARIA', () => {
    const wrapper = mountShell();
    const tabs = wrapper.findAll('[role="tab"]');

    expect(tabs.map(tab => tab.attributes('id'))).toEqual([
      'agent-panel-tab-performance',
      'agent-panel-tab-test',
      'agent-panel-tab-knowledge',
      'agent-panel-tab-channels',
      'agent-panel-tab-tune',
      'agent-panel-tab-tools',
    ]);
    expect(tabs[0].attributes('aria-selected')).toBe('true');
    expect(tabs[0].attributes('aria-controls')).toBe(
      'agent-panel-panel-performance'
    );
    expect(wrapper.get('[role="tabpanel"]').attributes('aria-labelledby')).toBe(
      'agent-panel-tab-performance'
    );
  });

  it('navega pelo conjunto visível com setas, Home e End', async () => {
    const wrapper = mountShell({
      visibleTabs: ['performance', 'test', 'knowledge'],
    });
    const list = wrapper.get('[role="tablist"]');

    await list.trigger('keydown', { key: 'ArrowRight' });
    await list.trigger('keydown', { key: 'End' });
    await list.trigger('keydown', { key: 'Home' });

    expect(wrapper.emitted('tabChange')).toEqual([
      ['test'],
      ['knowledge'],
      ['performance'],
    ]);
  });

  it('foca e rola a aba escolhida para mantê-la visível', async () => {
    const wrapper = mountShell({
      visibleTabs: ['performance', 'test', 'knowledge'],
    });
    const target = wrapper.get('#agent-panel-tab-test').element;
    const scrollIntoView = vi.fn();
    target.scrollIntoView = scrollIntoView;

    await wrapper.get('[role="tablist"]').trigger('keydown', {
      key: 'ArrowRight',
    });
    await new Promise(resolve => {
      requestAnimationFrame(resolve);
    });

    expect(document.activeElement).toBe(target);
    expect(scrollIntoView).toHaveBeenCalledWith({
      block: 'nearest',
      inline: 'nearest',
    });
  });

  it('mostra a aba ativa no mount e ao trocar a rota sem roubar o foco', async () => {
    const originalScrollIntoView = HTMLElement.prototype.scrollIntoView;
    const scrollIntoView = vi.fn();
    HTMLElement.prototype.scrollIntoView = scrollIntoView;

    try {
      const wrapper = mountShell({
        activeTab: 'channels',
        visibleTabs: ['performance', 'test', 'knowledge', 'channels', 'tune'],
      });
      await new Promise(resolve => {
        requestAnimationFrame(resolve);
      });

      expect(scrollIntoView).toHaveBeenCalledWith({
        block: 'nearest',
        inline: 'nearest',
      });

      const focusSentinel = document.createElement('button');
      focusSentinel.type = 'button';
      document.body.appendChild(focusSentinel);
      focusSentinel.focus();
      scrollIntoView.mockClear();

      await wrapper.setProps({ activeTab: 'tune' });
      await new Promise(resolve => {
        requestAnimationFrame(resolve);
      });

      expect(scrollIntoView).toHaveBeenCalledWith({
        block: 'nearest',
        inline: 'nearest',
      });
      expect(document.activeElement).toBe(focusSentinel);
      focusSentinel.remove();
    } finally {
      HTMLElement.prototype.scrollIntoView = originalScrollIntoView;
    }
  });

  it('aceita a projeção restrita para viewer sem expor edição ou ferramentas', () => {
    const wrapper = mountShell({
      canManage: false,
      visibleTabs: ['performance', 'test'],
      activeTab: 'test',
    });

    expect(wrapper.findAll('[role="tab"]').map(tab => tab.text())).toHaveLength(
      2
    );
    expect(wrapper.find('[data-action="continue-building"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-action="toggle-status"]').exists()).toBe(false);
  });

  it('usa o interruptor aprovado nos estados E5 e E6, em desktop e móvel', async () => {
    const activeWrapper = mountShell();
    const activeSwitches = activeWrapper.findAll('[role="switch"]');

    expect(activeSwitches).toHaveLength(2);
    activeSwitches.forEach(control => {
      expect(control.attributes('aria-checked')).toBe('true');
      expect(control.attributes('aria-label')).toBe('Active: Clara');
      expect(control.text()).toContain('Active');
    });

    const wrapper = mountShell({
      agent: {
        ...agent,
        state: { code: 'E6' },
        status: 'active',
        enabled: false,
      },
    });

    const control = wrapper.get('[data-testid="agent-panel-action-activate"]');
    expect(control.attributes('role')).toBe('switch');
    expect(control.attributes('aria-checked')).toBe('false');
    expect(control.attributes('aria-label')).toBe('Paused: Clara');
    expect(control.text()).toContain('Paused');
    expect(
      wrapper.get('[data-action="toggle-status-mobile"]').attributes('role')
    ).toBe('switch');

    await control.trigger('click');
    expect(wrapper.emitted('toggle-status')).toHaveLength(1);
  });

  it('desabilita os dois interruptores durante a atualização do estado', () => {
    const wrapper = mountShell({ isTogglingStatus: true });

    wrapper.findAll('[role="switch"]').forEach(control => {
      expect(control.attributes('disabled')).toBeDefined();
    });
  });

  it('mantém o aviso de Cotação visível em todas as abas', () => {
    const wrapper = mountShell({
      agent: { ...agent, agent_type: 'insurance_quote' },
      activeTab: 'knowledge',
      visibleTabs: ['performance', 'test', 'knowledge'],
    });

    const notice = wrapper.get('[data-state="quote-notice"]');
    expect(notice.text()).toContain('Clara');
    expect(notice.text()).toContain('Hub2You');
    expect(notice.text()).toContain('Open Quoting');
    expect(
      wrapper.get('[data-router-link]').attributes('data-route-name')
    ).toBe('autonomia_insurance');
    expect(
      wrapper.get('[data-router-link]').attributes('data-account-id')
    ).toBe('7');
  });
});
