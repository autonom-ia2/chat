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
const render = async (locale = 'en', detalhe = true) => {
  CrmKanbanAPI.getAiSettings.mockResolvedValue({ data: { payload: config() } });
  CrmKanbanAPI.updateAiSettings.mockImplementation(async (_id, body) => ({
    data: { payload: body.ai_settings },
  }));
  const wrapper = mount(Panel, {
    props: { pipelineId: 426, detalhe },
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

const pressedDays = wrapper =>
  wrapper.findAll(
    '[aria-labelledby="followup-days-label"] button[aria-pressed="true"]'
  );

describe('AI follow-up settings', () => {
  it('opens on a ready-made summary with a single "Change" for the details', async () => {
    const wrapper = await render('pt_BR', false);
    expect(wrapper.get('[data-followup-resumo]').text()).toBe(
      'Chamamos de volta 3 vezes: em 6 horas, em 3 dias e em 1 semana.'
    );
    expect(wrapper.text()).toContain('De segunda a sexta, das 8h às 20h.');
    expect(wrapper.find('[data-followup-touch]').exists()).toBe(false);

    await wrapper.get('[data-followup-alterar]').trigger('click');
    expect(wrapper.emitted('alterar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('hides the writing style in reminder mode and saves mode and weekdays', async () => {
    const wrapper = await render();
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    expect(wrapper.text()).toContain('The customer receives nothing.');
    expect(wrapper.find('textarea').exists()).toBe(false);
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
    expect(pressedDays(wrapper)).toHaveLength(1);
    wrapper.unmount();
  });

  it('retains instructions and days when switching back to automatic messages', async () => {
    const wrapper = await render();
    await wrapper.get('textarea').setValue('Orientação específica');
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    await wrapper.get('input[value="auto_send"]').setValue(true);
    expect(wrapper.get('textarea').element.value).toBe('Orientação específica');
    expect(pressedDays(wrapper)).toHaveLength(5);
    // #1384: sem aviso técnico nem selo por tentativa.
    expect(wrapper.text()).not.toContain('WhatsApp');
    wrapper.unmount();
  });

  it('lists the attempts in order and keeps each after the previous one', async () => {
    const wrapper = await render();
    expect(wrapper.findAll('[data-followup-touch]')).toHaveLength(3);

    await wrapper.get('[data-vezes="1"]').trigger('click');
    expect(wrapper.vm.form.autoFollowup.intervalsHours).toEqual([6]);
    await wrapper.get('[data-vezes="3"]').trigger('click');
    const intervals = wrapper.vm.form.autoFollowup.intervalsHours;
    expect(intervals).toHaveLength(3);
    expect(intervals[1]).toBeGreaterThan(intervals[0]);
    expect(intervals[2]).toBeGreaterThan(intervals[1]);
    wrapper.unmount();
  });

  it('renders both actions in Portuguese without English fallback', async () => {
    const wrapper = await render('pt_BR');
    expect(wrapper.text()).toContain('Mandar mensagem ao cliente');
    expect(wrapper.get('button[aria-label="Segunda-feira"]').text()).toBe(
      'Seg'
    );
    await wrapper.get('input[value="ai_reminder"]').setValue(true);
    expect(wrapper.text()).toContain('O cliente não recebe nada.');
    expect(wrapper.text()).not.toContain('CRM_KANBAN.');
    expect(wrapper.text()).not.toContain('CRM_FUNIL.');
    wrapper.unmount();
  });

  it('can disable a follow-up even when its hidden schedule is invalid', async () => {
    const wrapper = await render('pt_BR', false);
    wrapper.vm.form.autoFollowup.intervalsHours = [8, 8, 8];
    const enabled = wrapper.findAll('input[type="checkbox"]').at(-1);
    await enabled.setValue(false);
    expect(await wrapper.vm.saveSettings()).toBe(true);
    expect(CrmKanbanAPI.updateAiSettings).toHaveBeenLastCalledWith(
      426,
      expect.objectContaining({
        ai_settings: expect.objectContaining({
          auto_followup: { enabled: false },
        }),
      })
    );
    wrapper.unmount();
  });

  it('rejects an attempt that is not after the previous one before saving', async () => {
    const wrapper = await render();
    CrmKanbanAPI.updateAiSettings.mockClear();
    wrapper.vm.form.autoFollowup.intervalsHours = [72, 72, 168];
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('Pick a longer time');
    expect(await wrapper.vm.saveSettings()).toBe(false);
    expect(CrmKanbanAPI.updateAiSettings).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('reports failure to the parent when persistence fails', async () => {
    const wrapper = await render();
    CrmKanbanAPI.updateAiSettings.mockRejectedValue(new Error('unavailable'));
    expect(await wrapper.vm.saveSettings({ silent: true })).toBe(false);
    wrapper.unmount();
  });
});

// #1498 — lembretes de Atender: carregam do servidor, mudam no interruptor e
// vão no salvar.
describe('Serve reminders', () => {
  const montar = async (payload, modelo = 'COBRANCA') => {
    CrmKanbanAPI.getAiSettings.mockResolvedValue({ data: { payload } });
    CrmKanbanAPI.updateAiSettings.mockImplementation(async (_id, body) => ({
      data: { payload: body.ai_settings },
    }));
    const wrapper = mount(Panel, {
      props: {
        pipelineId: 7,
        detalhe: false,
        atender: true,
        modelo,
        sucesso: modelo === 'COBRANCA' ? 'Pago' : 'Resolvido',
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            fallbackLocale: false,
            messages: { en, pt_BR },
          }),
        ],
      },
    });
    await flushPromises();
    return wrapper;
  };

  it('shows only the payment reminder in Collections and saves it turned off', async () => {
    const wrapper = await montar({
      ...config(),
      service_reminders: {
        progress: false,
        resolved_check: false,
        payment: true,
      },
    });
    const lembretes = wrapper.findAll('[data-lembrete]');
    expect(lembretes.map(item => item.attributes('data-lembrete'))).toEqual([
      'payment',
    ]);
    expect(lembretes[0].text()).toContain('Lembrar do pagamento');

    await lembretes[0].get('input[role="switch"]').setValue(false);
    await wrapper.vm.saveSettings({ silent: true });

    const [[, body]] = CrmKanbanAPI.updateAiSettings.mock.calls.slice(-1);
    expect(body.ai_settings.service_reminders).toEqual({
      progress: false,
      resolved_check: false,
      payment: false,
      progress_after_hours: 24,
      resolved_check_after_hours: 24,
    });
    wrapper.unmount();
  });

  // #1589 — o tempo escolhido na frase vai no salvar; o salvo volta marcado.
  it('loads the saved time, lets the user pick another in the sentence and saves it', async () => {
    const wrapper = await montar(
      {
        ...config(),
        service_reminders: {
          progress: true,
          resolved_check: true,
          payment: false,
          progress_after_hours: 72,
          resolved_check_after_hours: 24,
        },
      },
      'ATENDIMENTO'
    );
    const andamento = wrapper.get('[data-lembrete="progress"]');
    expect(andamento.get('[data-tempo="72"]').attributes('aria-checked')).toBe(
      'true'
    );

    await andamento.get('[data-tempo="4"]').trigger('click');
    const resolveu = wrapper.get('[data-lembrete="resolved_check"]');
    await resolveu.get('[data-tempo="168"]').trigger('click');
    await resolveu.get('[data-tempo="168"]').trigger('keydown', {
      key: 'ArrowRight',
    });
    await wrapper.vm.saveSettings({ silent: true });

    const [[, body]] = CrmKanbanAPI.updateAiSettings.mock.calls.slice(-1);
    expect(body.ai_settings.service_reminders).toEqual({
      progress: true,
      resolved_check: true,
      payment: false,
      progress_after_hours: 4,
      resolved_check_after_hours: 24,
    });
    wrapper.unmount();
  });

  it('does not show Serve reminders in a Sell pipeline', async () => {
    CrmKanbanAPI.getAiSettings.mockResolvedValue({
      data: { payload: config() },
    });
    const wrapper = mount(Panel, {
      props: { pipelineId: 8, detalhe: false },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            fallbackLocale: false,
            messages: { en, pt_BR },
          }),
        ],
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-lembretes-atender]').exists()).toBe(false);
    wrapper.unmount();
  });
});
