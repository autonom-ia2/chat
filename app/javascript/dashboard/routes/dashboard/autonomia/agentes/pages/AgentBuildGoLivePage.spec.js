import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import { mount } from '@vue/test-utils';
import enAgents from 'dashboard/i18n/locale/en/agents.json';
import ptAgents from 'dashboard/i18n/locale/pt_BR/agents.json';
import AgentBuildGoLivePage from './AgentBuildGoLivePage.vue';

const channels = [
  { id: 11, name: 'Site', provider: 'Web' },
  { id: 12, name: 'Comercial', provider: 'E-mail' },
];

const mountPage = async (props = {}, locale = 'pt_BR') => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/accounts/:accountId', name: 'account', component: {} },
      {
        path: '/accounts/:accountId/settings/inboxes/new',
        name: 'settings_inbox_new',
        component: {},
      },
    ],
  });
  await router.push({ name: 'account', params: { accountId: 85 } });
  await router.isReady();

  const i18n = createI18n({
    legacy: false,
    locale,
    messages: { en: enAgents, pt_BR: ptAgents },
  });

  const wrapper = mount(AgentBuildGoLivePage, {
    props: {
      agent: { id: 42, name: 'Bia', actuation: 'external' },
      channels,
      testValid: true,
      ...props,
    },
    global: { plugins: [router, i18n] },
  });

  return wrapper;
};

describe('AgentBuildGoLivePage', () => {
  it('pré-seleciona a única caixa elegível, mas permite desmarcá-la', async () => {
    const wrapper = await mountPage({ channels: [channels[0]] });
    const option = wrapper.get('[role="checkbox"]');

    expect(option.attributes('aria-checked')).toBe('true');

    await option.trigger('click');
    expect(option.attributes('aria-checked')).toBe('false');
    expect(
      wrapper
        .get('[data-testid="creation-live-publish"]')
        .attributes('disabled')
    ).toBeDefined();

    await wrapper.setProps({ channels: [{ ...channels[0] }] });
    expect(option.attributes('aria-checked')).toBe('false');
    wrapper.unmount();
  });

  it('começa sem seleção e permite marcar várias com checkboxes', async () => {
    const wrapper = await mountPage();
    const options = wrapper.findAll('[role="checkbox"]');

    expect(options).toHaveLength(2);
    expect(options[0].attributes('aria-checked')).toBe('false');
    expect(options[1].attributes('aria-checked')).toBe('false');
    expect(options[0].attributes('data-channel-id')).toBe('11');

    await options[0].trigger('click');
    await options[1].trigger('click');
    expect(options[0].attributes('aria-checked')).toBe('true');
    expect(options[1].attributes('aria-checked')).toBe('true');
    expect(wrapper.text()).toContain('Caixas selecionadas (2)');

    await wrapper.get('[data-testid="creation-live-publish"]').trigger('click');
    expect(wrapper.emitted('publish')).toEqual([
      [{ inboxIds: [11, 12], responseWindow: 'always' }],
    ]);

    wrapper.unmount();
  });

  it('permite desmarcar uma ou todas e não remarca após atualizar a lista', async () => {
    const wrapper = await mountPage();
    const options = wrapper.findAll('[role="checkbox"]');

    await options[0].trigger('click');
    await options[1].trigger('click');
    expect(options[0].attributes('aria-checked')).toBe('true');
    expect(options[1].attributes('aria-checked')).toBe('true');

    await options[0].trigger('click');
    expect(options[0].attributes('aria-checked')).toBe('false');
    expect(options[1].attributes('aria-checked')).toBe('true');

    await options[1].trigger('click');
    expect(options[1].attributes('aria-checked')).toBe('false');
    expect(
      wrapper
        .get('[data-testid="creation-live-publish"]')
        .attributes('disabled')
    ).toBeDefined();

    await wrapper.setProps({ channels: [...channels] });
    expect(options[0].attributes('aria-checked')).toBe('false');
    expect(options[1].attributes('aria-checked')).toBe('false');

    wrapper.unmount();
  });

  it('mantém a ligação interna sem caixas e envia uma lista vazia', async () => {
    const wrapper = await mountPage({
      agent: { id: 42, name: 'Lia', actuation: 'internal' },
      channels: [],
    });

    await wrapper.get('[data-testid="creation-live-publish"]').trigger('click');
    expect(wrapper.emitted('publish')).toEqual([
      [{ inboxIds: [], responseWindow: 'always' }],
    ]);

    wrapper.unmount();
  });

  it('mantém caixas ocupadas desabilitadas', async () => {
    const wrapper = await mountPage({
      channels: [],
      occupiedChannels: [
        {
          id: 21,
          name: 'Ocupada',
          occupied_by: { kind: 'other_bot' },
        },
      ],
    });

    expect(wrapper.find('[role="radio"]').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });
});
