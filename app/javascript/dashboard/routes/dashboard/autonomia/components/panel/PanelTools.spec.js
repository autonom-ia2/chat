import { flushPromises, mount } from '@vue/test-utils';
import PanelTools from './PanelTools.vue';

// #1301 — o painel antigo continua para as contas sem a jornada nova. O modelo de estoque passou a
// usar um exemplo genérico (decisão do Rodrigo, 11/10/2026): nenhuma URL de cliente real.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const api = vi.hoisted(() => ({ getTools: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: api }));

describe('PanelTools · modelo de estoque', () => {
  it('fills the stock template with a generic address, never a customer one', async () => {
    api.getTools.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mount(PanelTools, { props: { agentId: 7 } });
    await flushPromises();
    await wrapper.findAll('button')[0].trigger('click');
    const valores = wrapper.findAll('input').map(input => input.element.value);
    expect(valores).toContain('https://api.sualoja.com.br/estoque/busca');
    expect(wrapper.html()).not.toContain('gira');
    wrapper.unmount();
  });
});
