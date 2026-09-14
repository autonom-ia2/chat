import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Panel from './CrmAiSettingsPanel.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getAiSettings: vi.fn(), updateAiSettings: vi.fn() },
}));

const config = () => ({
  enabled: true,
  auto_followup: {
    enabled: true,
    mode: 'auto_send',
    max_touches: 3,
    intervals_hours: [6, 72, 168],
    allowed_days: [1, 2, 3, 4, 5],
    quiet_hours: { start: 8, end: 20, tz: 'contact' },
    tone_instructions: 'Retome apenas pendências reais.',
  },
});
const render = async (locale = 'en') => {
  CrmKanbanAPI.getAiSettings.mockResolvedValue({ data: { payload: config() } });
  CrmKanbanAPI.updateAiSettings.mockImplementation(async (_id, body) => ({
    data: { payload: body.ai_settings },
  }));
  const wrapper = mount(Panel, {
    props: { pipelineId: 426 },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          fallbackLocale: false,
          messages: { en, pt_BR },
        }),
      ],
    },
  });
  await flushPromises();
  return wrapper;
};

describe('AI follow-up settings', () => {
  it('keeps AI instructions in reminder mode and saves mode and weekdays', async () => {
    const wrapper = await render();
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    expect(wrapper.text()).toContain('No message is sent to the customer');
    expect(wrapper.get('textarea').element.value).toBe(
      'Retome apenas pendências reais.'
    );
    await wrapper.get('button[aria-label="Saturday"]').trigger('click');
    await wrapper.vm.saveSettings();
    expect(CrmKanbanAPI.updateAiSettings).toHaveBeenCalledWith(
      426,
      expect.objectContaining({
        ai_settings: expect.objectContaining({
          auto_followup: expect.objectContaining({
            mode: 'ai_reminder',
            allowed_days: [1, 2, 3, 4, 5, 6],
            tone_instructions: 'Retome apenas pendências reais.',
          }),
        }),
      })
    );
    wrapper.unmount();
  });

  it('never permits clearing the last selected weekday', async () => {
    const wrapper = await render();
    await Promise.all(
      ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'].map(day =>
        wrapper.get(`button[aria-label="${day}"]`).trigger('click')
      )
    );
    expect(wrapper.findAll('button[aria-pressed="true"]')).toHaveLength(1);
    wrapper.unmount();
  });

  it('retains instructions and days when switching back to automatic messages', async () => {
    const wrapper = await render();
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    await wrapper.get('textarea').setValue('Orientação específica');
    await wrapper.get('input[value="auto_send"]').setValue(true);
    expect(wrapper.get('textarea').element.value).toBe('Orientação específica');
    expect(wrapper.findAll('button[aria-pressed="true"]')).toHaveLength(5);
    expect(wrapper.text()).toContain('Official WhatsApp');
    wrapper.unmount();
  });
  it('renders both actions in Portuguese without English fallback', async () => {
    const wrapper = await render('pt_BR');
    expect(wrapper.text()).toContain('IA envia ao cliente');
    expect(wrapper.text()).toContain('WhatsApp oficial:');
    expect(wrapper.get('button[aria-label="Segunda-feira"]').text()).toBe(
      'Seg'
    );
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    expect(wrapper.text()).toContain('Nenhuma mensagem é enviada ao cliente.');
    expect(wrapper.text()).toContain('Instruções para a IA');
    expect(wrapper.text()).not.toContain('WhatsApp oficial:');
    expect(wrapper.text()).not.toContain('CRM_KANBAN.');
    expect(
      pt_BR.CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.TIMELINE_TOUCH_REMINDER
    ).toContain('lembrete para a equipe');
    wrapper.unmount();
  });

  it('reports failure to the parent when persistence fails', async () => {
    const wrapper = await render();
    CrmKanbanAPI.updateAiSettings.mockRejectedValue(new Error('unavailable'));
    expect(await wrapper.vm.saveSettings({ silent: true })).toBe(false);
    wrapper.unmount();
  });
});
