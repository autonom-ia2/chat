import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import en from 'dashboard/i18n/locale/en/agents.json';
import PanelContracted from './PanelContracted.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const mounted = [];
const update = vi.fn();
const flags = reactive({ updatingItem: false });
const agent = {
  id: 7,
  name: 'Customer agent',
  company_name: 'Customer company',
  supplemental_instruction: 'Customer instructions',
};
const render = () => {
  const wrapper = mount(PanelContracted, {
    props: { agent },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        createStore({
          modules: {
            autonomiaAgents: {
              namespaced: true,
              getters: { getUIFlags: () => flags },
              actions: { update },
            },
          },
        }),
      ],
    },
  });
  mounted.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  flags.updatingItem = false;
  update.mockResolvedValue({});
});
afterEach(() => mounted.splice(0).forEach(wrapper => wrapper.unmount()));

describe('Contracted agent configuration', () => {
  it('saves only local identity and complements, never the principal link or inherited prompt', async () => {
    const wrapper = render();
    await wrapper.findAll('input')[0].setValue('New agent');
    await wrapper.findAll('input')[1].setValue('New company');
    await wrapper.get('textarea').setValue('New local detail');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    const payload = update.mock.calls[0][1];
    expect(payload).toMatchObject({
      id: 7,
      name: 'New agent',
      company_name: 'New company',
      supplemental_instruction: 'New local detail',
    });
    expect(payload).not.toHaveProperty('principal_agent_id');
    expect(payload).not.toHaveProperty('instruction');
    expect(payload).not.toHaveProperty('scaffold');
  });

  it('associates labels and enforces the complement limit in the actual textarea', () => {
    const wrapper = render();
    const area = wrapper.get('textarea');
    expect(area.attributes('maxlength')).toBe('50000');
    expect(wrapper.get(`label[for="${area.attributes('id')}"]`).text()).toBe(
      'Additional instructions'
    );
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('blocks repeated saves and empty names', async () => {
    const wrapper = render();
    flags.updatingItem = true;
    await wrapper.get('form').trigger('submit');
    expect(update).not.toHaveBeenCalled();
    flags.updatingItem = false;
    await wrapper.findAll('input')[0].setValue(' ');
    await wrapper.get('form').trigger('submit');
    expect(update).not.toHaveBeenCalled();
  });

  it('loads the next instance without carrying the previous tenant complements', async () => {
    const wrapper = render();
    await wrapper.setProps({
      agent: { id: 8, name: 'Another agent', company_name: 'Another company' },
    });
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.findAll('input')[1].element.value).toBe('Another company');
  });
});
