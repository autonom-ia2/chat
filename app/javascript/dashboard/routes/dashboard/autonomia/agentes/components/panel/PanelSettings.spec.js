import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PanelSettings from './PanelSettings.vue';

withFullI18n();
enableAutoUnmount(afterEach);

const sectionStub = name => ({
  name,
  props: ['agent', 'agentId', 'canManage', 'resumeBuild'],
  template: `<section data-test="${name}"></section>`,
});

const baseAgent = {
  id: 42,
  name: 'Clara',
  agent_type: 'standard',
  actuation: 'external',
  mode: 'guided',
  config: {},
};

const mountPanel = agent =>
  mount(PanelSettings, {
    props: {
      agentId: agent.id,
      agent,
      canManage: true,
      resumeBuild: false,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsIdentity: sectionStub('settings-identity'),
        SettingsInstructions: sectionStub('settings-instructions'),
        SettingsActuation: sectionStub('settings-actuation'),
        SettingsSpeech: sectionStub('settings-speech'),
        SettingsHandoff: sectionStub('settings-handoff'),
        SettingsAudience: sectionStub('settings-audience'),
        SettingsSchedule: sectionStub('settings-schedule'),
        SettingsVersions: sectionStub('settings-versions'),
        SettingsLifecycle: sectionStub('settings-lifecycle'),
        SettingsQuote: sectionStub('settings-quote'),
      },
    },
  });

describe('PanelSettings', () => {
  it('separa as seções de atendimento e mantém o payload por seção', () => {
    const wrapper = mountPanel(baseAgent);

    expect(wrapper.find('[data-test="settings-identity"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-instructions"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test="settings-speech"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-handoff"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-audience"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-schedule"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-versions"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-quote"]').exists()).toBe(false);
  });

  it('não mostra controles de cliente para o ajudante interno', () => {
    const wrapper = mountPanel({ ...baseAgent, actuation: 'internal' });

    expect(wrapper.find('[data-test="settings-instructions"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test="settings-speech"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-handoff"]').exists()).toBe(false);
    expect(wrapper.find('[data-test="settings-audience"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-test="settings-schedule"]').exists()).toBe(
      false
    );
  });

  it('troca o conjunto de seções pelo conjunto próprio do agente de cotação', () => {
    const wrapper = mountPanel({
      ...baseAgent,
      agent_type: 'insurance_quote',
    });

    expect(wrapper.find('[data-test="settings-quote"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="settings-instructions"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-test="settings-speech"]').exists()).toBe(false);
    expect(wrapper.find('[data-test="settings-versions"]').exists()).toBe(
      false
    );
  });
});
