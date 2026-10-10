import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsWhatsappReport from '../components/MetaAdsWhatsappReport.vue';
import CrmMetaAdsWhatsappReportAPI from 'dashboard/api/crmMetaAdsWhatsappReport';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsWhatsappReport', () => ({
  default: { get: vi.fn(), update: vi.fn(), sendTest: vi.fn() },
}));

const WAHA = {
  inbox_id: 5,
  name: 'Vendas',
  phone_number: '+5511999990000',
  kind: 'waha',
  templates: null,
};
const OFFICIAL = {
  inbox_id: 9,
  name: 'Oficial',
  phone_number: '+5511888880000',
  kind: 'whatsapp_cloud',
  templates: { summary: 'approved', alert: 'pending' },
};

const report = (overrides = {}) => ({
  enabled: false,
  alert_enabled: false,
  inbox_id: null,
  phone: null,
  last_summary_at: null,
  last_alert_at: null,
  last_error: null,
  last_error_at: null,
  origins: [WAHA, OFFICIAL],
  template_texts: {
    summary: { name: 'chat2you_resumo_anuncios', body: 'Resumo {{1}}' },
    alert: { name: 'chat2you_alerta_anuncio', body: 'Atenção {{1}}' },
  },
  schedule: {
    summary_local_time: '08:00',
    alert_local_time: '16:30',
    time_zone: 'America/Sao_Paulo',
  },
  ...overrides,
});

const serverError = (code, status = 422) =>
  Object.assign(new Error(code), {
    response: { status, data: { error: code } },
  });

let mounted = null;

const mountReport = async data => {
  CrmMetaAdsWhatsappReportAPI.get.mockResolvedValue({
    data: { whatsapp_report: data },
  });
  mounted = mount(MetaAdsWhatsappReport, {
    global: {
      stubs: {
        Button: {
          props: ['label', 'disabled', 'isLoading'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
        ChoiceSelect: {
          props: ['modelValue', 'groups', 'invalid'],
          emits: ['update:modelValue', 'change'],
          template: `<div data-choice :data-value="modelValue" :data-invalid="invalid">
            <div v-for="group in groups" :key="group.label" :data-group="group.label">
              <button v-for="option in group.options" :key="option.value"
                :data-option="option.value"
                @click="$emit('update:modelValue', option.value); $emit('change', option.value)">
                {{ option.label }}
              </button>
            </div>
          </div>`,
        },
      },
    },
  });
  await flushPromises();
  return mounted;
};

const PREFIX = 'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT';

describe('Anúncios da Meta · resumo no WhatsApp (#1100, F4b)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
  });

  it('starts off and lists only the connected numbers the server returns, grouped by kind', async () => {
    const wrapper = await mountReport(report());

    expect(CrmMetaAdsWhatsappReportAPI.get).toHaveBeenCalledTimes(1);
    const toggles = wrapper.findAll('[role="switch"]');
    expect(toggles.map(node => node.attributes('aria-checked'))).toEqual([
      'false',
      'false',
    ]);
    const groups = wrapper.findAll('[data-group]');
    expect(groups.map(node => node.attributes('data-group'))).toEqual([
      `${PREFIX}.KIND.WHATSAPP_CLOUD`,
      `${PREFIX}.KIND.WAHA`,
    ]);
    expect(wrapper.find('[data-option="5"]').text()).toContain('Vendas');
    expect(wrapper.find('[data-option="5"]').text()).toContain('+55 11 99999');
    expect(wrapper.find('[data-report-templates]').exists()).toBe(false);
    expect(wrapper.find('[data-report-test]').attributes('disabled')).toBe('');
    expect(wrapper.find('[data-report-test-hint]').exists()).toBe(true);
  });

  it('says there is no connected number instead of an empty list', async () => {
    const wrapper = await mountReport(report({ origins: [] }));

    expect(wrapper.find('[data-choice]').exists()).toBe(false);
    expect(wrapper.find('[data-report-no-origins]').text()).toContain(
      'ORIGIN_EMPTY'
    );
  });

  it('renders nothing to configure without a Meta connection', async () => {
    const wrapper = await mountReport(null);

    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-report-save]').exists()).toBe(false);
  });

  it('saves only what changed, with the phone as typed for the server to validate', async () => {
    CrmMetaAdsWhatsappReportAPI.update.mockResolvedValue({
      data: {
        whatsapp_report: report({
          enabled: true,
          inbox_id: 5,
          phone: '+5511977776666',
        }),
      },
    });
    const wrapper = await mountReport(report());

    expect(wrapper.find('[data-report-save]').attributes('disabled')).toBe('');
    await wrapper.find('[data-report-toggle="enabled"]').trigger('click');
    await wrapper.find('[data-option="5"]').trigger('click');
    await wrapper.find('[data-report-phone]').setValue(' (11) 97777-6666 ');
    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsWhatsappReportAPI.update).toHaveBeenCalledWith({
      enabled: true,
      inbox_id: 5,
      phone: '(11) 97777-6666',
    });
    expect(useAlert).toHaveBeenCalledWith(`${PREFIX}.SAVED`);
    expect(wrapper.find('[data-report-phone]').element.value).toBe(
      '+55 11 97777 6666'
    );
    expect(wrapper.find('[data-report-save]').attributes('disabled')).toBe('');
    expect(wrapper.find('[data-report-reply-note]').exists()).toBe(true);
  });

  it('turning off always goes to the server, even without origin', async () => {
    CrmMetaAdsWhatsappReportAPI.update.mockResolvedValue({
      data: { whatsapp_report: report({ alert_enabled: false }) },
    });
    const wrapper = await mountReport(report({ alert_enabled: true }));

    await wrapper.find('[data-report-toggle="alert_enabled"]').trigger('click');
    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsWhatsappReportAPI.update).toHaveBeenCalledWith({
      alert_enabled: false,
    });
  });

  it('shows the server phone error under the phone field', async () => {
    CrmMetaAdsWhatsappReportAPI.update.mockRejectedValue(
      serverError('invalid_phone')
    );
    const wrapper = await mountReport(report({ inbox_id: 5 }));

    await wrapper.find('[data-report-phone]').setValue('123');
    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();

    const input = wrapper.find('[data-report-phone]');
    expect(input.attributes('aria-invalid')).toBe('true');
    const error = wrapper.find('[data-report-phone-error]');
    expect(error.text()).toBe(`${PREFIX}.ERRORS.INVALID_PHONE`);
    expect(input.attributes('aria-describedby')).toBe(error.attributes('id'));
    expect(wrapper.find('[data-report-error]').exists()).toBe(false);

    await input.setValue('11977776666');
    expect(wrapper.find('[data-report-phone-error]').exists()).toBe(false);
  });

  it('shows origin errors on the origin and other codes next to the button', async () => {
    CrmMetaAdsWhatsappReportAPI.update
      .mockRejectedValueOnce(serverError('origin_required'))
      .mockRejectedValueOnce(serverError('template_not_approved'))
      .mockRejectedValueOnce(serverError('boom', 500));
    const wrapper = await mountReport(report());

    await wrapper.find('[data-report-toggle="enabled"]').trigger('click');
    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-report-origin-error]').text()).toBe(
      `${PREFIX}.ERRORS.ORIGIN_REQUIRED`
    );
    expect(wrapper.find('[data-choice]').attributes('data-invalid')).toBe(
      'true'
    );

    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-report-origin-error]').exists()).toBe(false);
    expect(wrapper.find('[data-report-error]').text()).toBe(
      `${PREFIX}.ERRORS.TEMPLATE_NOT_APPROVED`
    );

    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-report-error]').text()).toBe(
      `${PREFIX}.ERRORS.GENERIC`
    );
  });

  it('shows the Meta templates and their status for an official number', async () => {
    const wrapper = await mountReport(
      report({ inbox_id: 9, phone: '+5511977776666' })
    );

    expect(wrapper.find('[data-report-origin-kind]').text()).toContain(
      'KIND.WHATSAPP_CLOUD'
    );
    const summary = wrapper.find('[data-report-template="summary"]');
    const alert = wrapper.find('[data-report-template="alert"]');
    expect(summary.text()).toContain('chat2you_resumo_anuncios');
    expect(summary.text()).toContain('Resumo {{1}}');
    expect(
      summary
        .find('[data-report-template-status]')
        .attributes('data-report-template-status')
    ).toBe('approved');
    expect(
      alert
        .find('[data-report-template-status]')
        .attributes('data-report-template-status')
    ).toBe('pending');

    // Ligar o alerta sem o modelo aprovado avisa antes de salvar.
    expect(wrapper.find('[data-report-blocked]').exists()).toBe(false);
    await wrapper.find('[data-report-toggle="alert_enabled"]').trigger('click');
    expect(wrapper.find('[data-report-blocked="alert_enabled"]').exists()).toBe(
      true
    );
    await wrapper.find('[data-report-toggle="enabled"]').trigger('click');
    expect(wrapper.find('[data-report-blocked="enabled"]').exists()).toBe(
      false
    );
  });

  it('treats an unknown template status as not created', async () => {
    const wrapper = await mountReport(
      report({
        inbox_id: 9,
        origins: [{ ...OFFICIAL, templates: { summary: 'PAUSED' } }],
      })
    );

    const statuses = wrapper
      .findAll('[data-report-template-status]')
      .map(node => node.attributes('data-report-template-status'));
    expect(statuses).toEqual(['missing', 'missing']);
  });

  it('copies the template name and text', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText },
      configurable: true,
    });
    const wrapper = await mountReport(report({ inbox_id: 9 }));

    const buttons = wrapper
      .find('[data-report-template="alert"]')
      .findAll('button');
    await buttons[0].trigger('click');
    await buttons[1].trigger('click');
    await flushPromises();

    expect(writeText).toHaveBeenNthCalledWith(1, 'chat2you_alerta_anuncio');
    expect(writeText).toHaveBeenNthCalledWith(2, 'Atenção {{1}}');
    expect(useAlert).toHaveBeenCalledWith(`${PREFIX}.TEMPLATES.COPIED`);
  });

  it('warns when the saved number is no longer connected and blocks the test', async () => {
    const wrapper = await mountReport(
      report({ inbox_id: 77, phone: '+5511977776666' })
    );

    expect(wrapper.find('[data-report-origin-gone]').exists()).toBe(true);
    expect(wrapper.find('[data-report-test]').attributes('disabled')).toBe('');
    expect(
      wrapper.find('[data-report-test-hint]').attributes('data-test-blocker')
    ).toBe('NEEDS_ORIGIN');
  });

  it('tells why the test is blocked and lets a refused change be discarded', async () => {
    CrmMetaAdsWhatsappReportAPI.update.mockRejectedValueOnce(
      serverError('template_not_approved')
    );
    const wrapper = await mountReport(
      report({ enabled: true, inbox_id: 9, phone: '+5511977776666' })
    );
    const hint = () => wrapper.find('[data-report-test-hint]');
    expect(hint().exists()).toBe(false);
    expect(wrapper.find('[data-report-discard]').exists()).toBe(false);

    await wrapper.find('[data-report-toggle="alert_enabled"]').trigger('click');
    await wrapper.find('[data-report-save]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-report-test]').attributes('disabled')).toBe('');
    expect(hint().attributes('data-test-blocker')).toBe('NEEDS_SAVE_CHANGES');
    expect(hint().text()).toBe(`${PREFIX}.TEST_NEEDS_SAVE_CHANGES`);

    await wrapper.find('[data-report-discard]').trigger('click');

    expect(wrapper.find('[data-report-test]').attributes('disabled')).toBe(
      undefined
    );
    expect(wrapper.find('[data-report-error]').exists()).toBe(false);
    expect(wrapper.find('[data-report-discard]').exists()).toBe(false);
  });

  it('sends a test only with the saved setup and shows the result', async () => {
    CrmMetaAdsWhatsappReportAPI.sendTest
      .mockResolvedValueOnce({
        data: { sent: true, sent_at: '2026-10-07T13:42:00Z' },
      })
      .mockRejectedValueOnce(serverError('rate_limited', 429))
      .mockRejectedValueOnce(serverError('send_uncertain'));
    const wrapper = await mountReport(
      report({ inbox_id: 5, phone: '+5511977776666' })
    );

    const test = () => wrapper.find('[data-report-test]');
    expect(test().attributes('disabled')).toBeUndefined();

    await test().trigger('click');
    await flushPromises();
    const result = wrapper.find('[data-report-test-result]');
    expect(result.attributes('role')).toBe('status');
    expect(result.text()).toBe(`${PREFIX}.TEST_SENT`);

    await test().trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-report-test-result]').attributes('role')).toBe(
      'alert'
    );
    expect(wrapper.find('[data-report-test-result]').text()).toBe(
      `${PREFIX}.ERRORS.RATE_LIMITED`
    );

    await test().trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-report-test-result]').text()).toBe(
      `${PREFIX}.ERRORS.SEND_UNCERTAIN`
    );
    expect(CrmMetaAdsWhatsappReportAPI.sendTest).toHaveBeenCalledTimes(3);

    // Rascunho não é testado: mudou o número, precisa salvar antes.
    await wrapper.find('[data-report-phone]').setValue('11911112222');
    expect(test().attributes('disabled')).toBe('');
  });

  it('shows the last deliveries and the last problem', async () => {
    const wrapper = await mountReport(
      report({
        last_summary_at: new Date(Date.now() - 3 * 3600 * 1000).toISOString(),
        last_error: 'send_failed',
        last_error_at: new Date(Date.now() - 3600 * 1000).toISOString(),
      })
    );

    expect(
      wrapper.find('[data-report-history-row="summary"]').text()
    ).toContain('HISTORY.SUMMARY');
    expect(wrapper.find('[data-report-history-row="alert"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-report-last-error]').text()).toBe(
      `${PREFIX}.HISTORY.ERROR`
    );
  });

  it('tells "nothing to report" apart from a failure', async () => {
    const wrapper = await mountReport(
      report({
        last_error: 'nothing_to_report',
        last_error_at: new Date().toISOString(),
      })
    );

    const line = wrapper.find('[data-report-last-error]');
    expect(line.text()).toBe(`${PREFIX}.HISTORY.NOTHING_TO_REPORT`);
    expect(line.classes()).toContain('text-n-slate-11');
  });

  it('offers to try again when the load fails', async () => {
    CrmMetaAdsWhatsappReportAPI.get.mockRejectedValueOnce(
      serverError('x', 500)
    );
    mounted = mount(MetaAdsWhatsappReport, {
      global: {
        stubs: {
          Button: {
            props: ['label'],
            template: '<button>{{ label }}</button>',
          },
          ChoiceSelect: true,
        },
      },
    });
    await flushPromises();
    expect(mounted.find('[data-report-load-error]').exists()).toBe(true);

    CrmMetaAdsWhatsappReportAPI.get.mockResolvedValueOnce({
      data: { whatsapp_report: report() },
    });
    await mounted.find('[data-report-load-error] button').trigger('click');
    await flushPromises();
    expect(mounted.find('[data-report-load-error]').exists()).toBe(false);
    expect(mounted.findAll('[role="switch"]')).toHaveLength(2);
  });
});
