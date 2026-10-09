import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SettingsQuote from './SettingsQuote.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    updateQuoteChoices: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

const baseAgent = {
  id: 42,
  name: 'Clara',
  agent_type: 'insurance_quote',
  quote_choices: {
    name: 'Clara',
    behavior: 'consultivo',
    horario: '09:00-18:00',
  },
};

const mountSettings = agent =>
  mount(SettingsQuote, {
    props: {
      agentId: agent.id,
      agent,
      canManage: true,
    },
  });

describe('SettingsQuote', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.updateQuoteChoices.mockReset();
  });

  it('emite somente quote_choices do DTO completo e preserva escolhas no segundo PATCH', async () => {
    const firstResponse = {
      id: 42,
      name: 'Clara',
      agent_type: 'insurance_quote',
      quote_choices: {
        name: 'Clara',
        behavior: 'objetivo',
        horario: '08:00-17:00',
      },
      config: { response_window: 30 },
    };
    const secondResponse = {
      ...firstResponse,
      updated_at: '2026-10-08T12:00:00Z',
    };
    AutonomiaAgentsAPI.updateQuoteChoices
      .mockResolvedValueOnce({ data: firstResponse })
      .mockResolvedValueOnce({ data: secondResponse });

    const wrapper = mountSettings(baseAgent);
    await wrapper.find('#quote-objetivo').trigger('change');
    await wrapper
      .find('input[data-test="quote-schedule"]')
      .setValue('08:00-17:00');

    await wrapper.find('[data-test="quote-save"]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('saved')[0][0]).toEqual({
      quote_choices: firstResponse.quote_choices,
    });
    expect(wrapper.emitted('saved')[0][0].quote_choices).not.toEqual(
      firstResponse
    );

    await wrapper.setProps({
      agent: {
        ...baseAgent,
        ...wrapper.emitted('saved')[0][0],
      },
    });
    await wrapper.find('[data-test="quote-save"]').trigger('click');
    await flushPromises();

    expect(AutonomiaAgentsAPI.updateQuoteChoices).toHaveBeenNthCalledWith(
      1,
      42,
      {
        behavior: 'objetivo',
        horario: '08:00-17:00',
      }
    );
    expect(AutonomiaAgentsAPI.updateQuoteChoices).toHaveBeenNthCalledWith(
      2,
      42,
      {
        behavior: 'objetivo',
        horario: '08:00-17:00',
      }
    );
  });

  it('preserva o rascunho quando muda uma propriedade sem relação com as escolhas', async () => {
    const wrapper = mountSettings(baseAgent);

    await wrapper
      .find('input[data-test="quote-schedule"]')
      .setValue('10:00-19:00');
    await wrapper.setProps({
      agent: {
        ...baseAgent,
        name: 'Clara atualizada',
        updated_at: '2026-10-08T13:00:00Z',
      },
    });

    expect(
      wrapper.find('input[data-test="quote-schedule"]').element.value
    ).toBe('10:00-19:00');
  });
});
