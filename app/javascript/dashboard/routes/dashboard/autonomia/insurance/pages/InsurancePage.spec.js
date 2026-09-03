import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import InsurancePage from './InsurancePage.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
}));

describe('InsurancePage', () => {
  const mountPage = tab =>
    mount(InsurancePage, {
      props: { tab },
      global: {
        stubs: {
          InsuranceConnectionsTab: {
            template: '<div data-tab="connections" />',
          },
          InsuranceAgentTab: { template: '<div data-tab="agent" />' },
        },
      },
    });

  it('renders the two tabs and marks the active one', () => {
    const wrapper = mountPage('connections');
    const tabs = wrapper.findAll('[role="tab"]');

    expect(tabs).toHaveLength(2);
    expect(tabs[0].attributes('aria-selected')).toBe('true');
    expect(tabs[1].attributes('aria-selected')).toBe('false');
    expect(wrapper.find('[data-tab="connections"]').exists()).toBe(true);
    expect(wrapper.find('[data-tab="agent"]').exists()).toBe(false);
  });

  it('shows the agent tab content when tab=agent', () => {
    const wrapper = mountPage('agent');

    expect(wrapper.find('[data-tab="agent"]').exists()).toBe(true);
    expect(wrapper.findAll('[role="tab"]')[1].attributes('aria-selected')).toBe(
      'true'
    );
  });

  it('navigates by named route when another tab is clicked, and not for the current one', async () => {
    const wrapper = mountPage('connections');
    const tabs = wrapper.findAll('[role="tab"]');

    await tabs[0].trigger('click');
    expect(push).not.toHaveBeenCalled();

    await tabs[1].trigger('click');
    expect(push).toHaveBeenCalledWith({ name: 'autonomia_insurance_agent' });
  });
});
