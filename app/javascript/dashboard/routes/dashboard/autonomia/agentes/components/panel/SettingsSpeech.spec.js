import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SettingsSpeech from './SettingsSpeech.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { update: vi.fn() },
}));

withFullI18n();
enableAutoUnmount(afterEach);

const mountSpeech = (props = {}) =>
  mount(SettingsSpeech, {
    props: {
      agentId: 42,
      agent: {
        id: 42,
        greeting: 'Olá',
        fallback_message: 'Vou chamar a equipe.',
        tone: 'friendly',
      },
      canManage: true,
      ...props,
    },
  });

describe('SettingsSpeech', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.update.mockReset();
    AutonomiaAgentsAPI.update.mockResolvedValue({ data: { id: 42 } });
  });

  it('converte tom antigo apenas na leitura e salva a frase pt-BR', async () => {
    const wrapper = mountSpeech();

    await wrapper.find('[data-test="tone-professional"]').trigger('click');
    await wrapper.find('[data-test="speech-save"]').trigger('click');

    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith(42, {
      agent: {
        greeting: 'Olá',
        fallback_message: 'Vou chamar a equipe.',
        tone: 'Profissional',
      },
    });
  });

  it('não envia saudação quando o agente é interno', async () => {
    const wrapper = mountSpeech({ isInternal: true });

    await wrapper.find('[data-test="speech-save"]').trigger('click');

    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith(42, {
      agent: {
        fallback_message: 'Vou chamar a equipe.',
        tone: 'Amigável',
      },
    });
    expect(wrapper.find('[data-test="speech-greeting"]').exists()).toBe(false);
  });
});
