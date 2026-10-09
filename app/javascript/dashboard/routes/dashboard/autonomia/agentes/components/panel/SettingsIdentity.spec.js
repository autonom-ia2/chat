import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SettingsIdentity from './SettingsIdentity.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    update: vi.fn(),
    updateAvatar: vi.fn(),
    deleteAvatar: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

describe('SettingsIdentity', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.update.mockReset();
    AutonomiaAgentsAPI.update.mockResolvedValue({
      data: { id: 42, name: 'Clara', voice: 'masculina' },
    });
  });

  it('salva nome e tratamento com o campo voice tipado', async () => {
    const wrapper = mount(SettingsIdentity, {
      props: {
        agentId: 42,
        agent: { id: 42, name: 'Clara', voice: 'feminina' },
        canManage: true,
      },
    });

    await wrapper.find('[data-test="voice-masculina"]').trigger('click');
    await wrapper.find('[data-test="identity-save"]').trigger('click');

    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith(42, {
      agent: { name: 'Clara', voice: 'masculina' },
    });
  });

  it('preserva o rascunho quando outra seção atualiza o agente', async () => {
    const wrapper = mount(SettingsIdentity, {
      props: {
        agentId: 42,
        agent: { id: 42, name: 'Clara', voice: 'feminina' },
        canManage: true,
      },
    });

    await wrapper
      .find('input[data-test="identity-name"]')
      .setValue('Nome local');
    await wrapper.setProps({
      agent: {
        id: 42,
        name: 'Clara',
        voice: 'feminina',
        config: { response_window: 30 },
      },
    });

    expect(wrapper.find('input[data-test="identity-name"]').element.value).toBe(
      'Nome local'
    );
  });

  it('atualiza o avatar quando a própria foto muda sem apagar o rascunho do nome', async () => {
    const wrapper = mount(SettingsIdentity, {
      props: {
        agentId: 42,
        agent: { id: 42, name: 'Clara', voice: 'feminina' },
        canManage: true,
      },
    });

    await wrapper
      .find('input[data-test="identity-name"]')
      .setValue('Nome local');
    await wrapper.setProps({
      agent: {
        id: 42,
        name: 'Clara',
        voice: 'feminina',
        avatar_url: 'https://example.test/avatar-a.png',
      },
    });

    expect(wrapper.find('input[data-test="identity-name"]').element.value).toBe(
      'Nome local'
    );
    expect(wrapper.find('[role="img"] img').attributes('src')).toBe(
      'https://example.test/avatar-a.png'
    );
  });
});
