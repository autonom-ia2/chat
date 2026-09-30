import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import campaignMessages from 'dashboard/i18n/locale/en/campaign.json';
import protectionMessages from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import ptBrCampaignMessages from 'dashboard/i18n/locale/pt_BR/campaign.json';
import ptBrProtectionMessages from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import EmailCampaignReview from '../../Pages/CampaignPage/EmailCampaign/EmailCampaignReview.vue';

const dispatch = vi.hoisted(() => vi.fn());
const alert = vi.hoisted(() => vi.fn());
const canManage = vi.hoisted(() => ({ value: true }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => canManage,
}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue',
  () => ({ default: { template: '<div data-recipient-import-status />' } })
);

// Test-only child stub keeps this spec independent of the design-system bundle.
// eslint-disable-next-line vue/one-component-per-file
const ButtonStub = defineComponent({
  props: {
    label: { type: [String, Number], default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['click'],
  setup(props, { attrs, emit }) {
    return () =>
      h(
        'button',
        {
          ...attrs,
          type: attrs.type || 'button',
          disabled: props.disabled,
          onClick: () => emit('click'),
        },
        props.label
      );
  },
});

// Test-only child stub keeps this spec independent of the design-system bundle.
// eslint-disable-next-line vue/one-component-per-file
const DialogStub = defineComponent({
  props: {
    title: { type: String, default: '' },
    confirmButtonLabel: { type: String, default: 'Confirm' },
    disableConfirmButton: { type: Boolean, default: false },
  },
  emits: ['confirm', 'close'],
  setup(props, { expose, emit, slots }) {
    const isOpen = ref(false);
    expose({
      open: () => {
        isOpen.value = true;
      },
      close: () => {
        isOpen.value = false;
      },
    });

    return () =>
      isOpen.value
        ? h('div', { role: 'dialog', 'data-dialog': props.title }, [
            slots.default?.(),
            h(
              'button',
              {
                type: 'button',
                'data-dialog-cancel': true,
                onClick: () => {
                  isOpen.value = false;
                  emit('close');
                },
              },
              'Cancel'
            ),
            h(
              'button',
              {
                type: 'button',
                'data-dialog-confirm': true,
                disabled: props.disableConfirmButton,
                onClick: () => emit('confirm'),
              },
              props.confirmButtonLabel
            ),
          ])
        : null;
  },
});

const SpinnerStub = { template: '<span data-spinner />' };

const readyChecks = {
  subject: true,
  content: true,
  sender: true,
  recipients: true,
  import: true,
  hygiene: true,
  provider: true,
};

const campaign = (overrides = {}) => ({
  id: 42,
  name: 'Novidades Chat2You',
  status: 'draft',
  subject: 'Uma novidade para você',
  preheader: 'Veja o que preparamos.',
  body_html: '<p>Olá, {{ nome }}</p>',
  from_name: 'Hub2You',
  from_email: 'envios@example.org',
  reply_to: 'respostas@example.org',
  sender_domain: 'example.org',
  delivery_mode: 'ses',
  recipient_import: { status: 'completed' },
  send_readiness: {
    can_send: true,
    checks: readyChecks,
    eligible_recipients: 3,
    protected_recipients: 2,
  },
  ...overrides,
});

const defaultPlugins = config.global.plugins;
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: {
    en: { ...campaignMessages, ...protectionMessages },
    pt_BR: { ...ptBrCampaignMessages, ...ptBrProtectionMessages },
    zh_CN: { ...campaignMessages, ...protectionMessages },
  },
});

const mountReview = props =>
  mount(EmailCampaignReview, {
    props: { campaign: campaign(), ...props },
    global: {
      plugins: [i18n],
      stubs: {
        Button: ButtonStub,
        Dialog: DialogStub,
        Spinner: SpinnerStub,
      },
    },
  });

beforeAll(() => {
  config.global.plugins = [];
});

afterAll(() => {
  config.global.plugins = defaultPlugins;
});

beforeEach(() => {
  dispatch.mockReset();
  alert.mockReset();
  i18n.global.locale.value = 'en';
  dispatch.mockImplementation(action => {
    if (action === 'emailCampaigns/validateTemplate')
      return Promise.resolve({ missing: [] });
    return Promise.resolve({});
  });
});

it('requires a final confirmation before sending and leaves no send after cancel', async () => {
  const wrapper = mountReview();
  await flushPromises();

  const sendButton = wrapper
    .findAll('button')
    .find(button => button.text() === 'Send campaign');
  expect(sendButton).toBeDefined();
  expect(sendButton.attributes('disabled')).toBeUndefined();

  await sendButton.trigger('click');
  await flushPromises();
  expect(dispatch).not.toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
  expect(wrapper.find('[role="dialog"]').exists()).toBe(true);

  await wrapper.get('[data-dialog-cancel]').trigger('click');
  expect(dispatch).not.toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);

  await sendButton.trigger('click');
  await flushPromises();
  await wrapper.get('[data-dialog-confirm]').trigger('click');
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
});

it('keeps an incomplete campaign blocked and points the user back to correction', async () => {
  const wrapper = mountReview({
    campaign: campaign({
      subject: '',
      body_html: '',
      recipient_import: { status: 'processing' },
      send_readiness: {
        can_send: false,
        checks: {
          ...readyChecks,
          subject: false,
          content: false,
          import: false,
        },
        eligible_recipients: 0,
        protected_recipients: 0,
      },
    }),
  });
  await flushPromises();

  const sendButton = wrapper
    .findAll('button')
    .find(button => button.text() === 'Send campaign');
  expect(sendButton.attributes('disabled')).toBeDefined();
  expect(wrapper.text()).toContain(
    'Resolve the items marked above before sending.'
  );
  expect(wrapper.text()).toContain('Complete the email');

  await sendButton.trigger('click');
  expect(dispatch).not.toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
});

it('renders a draft without a sender safely and keeps confirmation blocked', async () => {
  const wrapper = mountReview({
    campaign: campaign({
      from_name: null,
      from_email: null,
      send_readiness: {
        can_send: false,
        checks: { ...readyChecks, sender: false },
        eligible_recipients: 3,
        protected_recipients: 1,
      },
    }),
  });
  await flushPromises();

  expect(wrapper.text()).not.toContain('null <null>');
  expect(wrapper.text()).not.toContain('undefined <undefined>');

  const sendButton = wrapper
    .findAll('button')
    .find(button => button.text() === 'Send campaign');
  expect(sendButton.attributes('disabled')).toBeDefined();

  await sendButton.trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(dispatch).not.toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
});

it('sends the chosen future time only after confirming the schedule', async () => {
  const wrapper = mountReview();
  await flushPromises();

  const later = wrapper
    .findAll('button')
    .find(button => button.text().includes('Schedule for later'));
  await later.trigger('click');
  await wrapper.get('input[type="date"]').setValue('2099-12-31');
  await wrapper.get('input[type="time"]').setValue('12:30');

  const scheduleButton = wrapper
    .findAll('button')
    .find(button => button.text() === 'Review schedule');
  expect(scheduleButton.attributes('disabled')).toBeUndefined();
  await scheduleButton.trigger('click');
  await flushPromises();
  expect(dispatch).not.toHaveBeenCalledWith(
    'emailCampaigns/schedule',
    expect.anything()
  );

  await wrapper.get('[data-dialog-confirm]').trigger('click');
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith(
    'emailCampaigns/schedule',
    expect.objectContaining({ id: 42, scheduledAt: expect.any(String) })
  );
});

it('fails closed when the readiness refresh fails before confirmation', async () => {
  const wrapper = mountReview();
  await flushPromises();

  dispatch.mockRejectedValueOnce(new Error('workspace refresh failed'));
  const sendButton = wrapper
    .findAll('button')
    .find(button => button.text() === 'Send campaign');

  await sendButton.trigger('click');
  await flushPromises();

  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(dispatch).not.toHaveBeenCalledWith('emailCampaigns/sendNow', 42);
  expect(wrapper.text()).toContain(
    'Could not complete this action. Please try again.'
  );
});

it.each(['pt_BR', 'zh_CN'])(
  'renders counts and schedule review for the %s profile locale without Intl errors',
  async profileLocale => {
    i18n.global.locale.value = profileLocale;
    const wrapper = mountReview({
      campaign: campaign({
        send_readiness: {
          can_send: true,
          checks: readyChecks,
          eligible_recipients: 1234,
          protected_recipients: 56,
        },
      }),
    });
    await flushPromises();

    const formattedEligible = new Intl.NumberFormat(
      profileLocale.replace('_', '-')
    ).format(1234);
    expect(wrapper.text()).toContain(formattedEligible);

    const later = wrapper
      .findAll('button')
      .find(button =>
        button
          .text()
          .includes(
            i18n.global.t('CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.DELIVERY.later')
          )
      );
    await later.trigger('click');
    await wrapper.get('input[type="date"]').setValue('2099-12-31');
    await wrapper.get('input[type="time"]').setValue('12:30');

    const reviewSchedule = wrapper
      .findAll('button')
      .find(
        button =>
          button.text() ===
          i18n.global.t('CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.REVIEW_SCHEDULE')
      );
    await reviewSchedule.trigger('click');
    await flushPromises();

    const expectedSchedule = new Intl.DateTimeFormat(
      profileLocale.replace('_', '-'),
      { dateStyle: 'medium', timeStyle: 'short' }
    ).format(new Date('2099-12-31T12:30'));
    expect(wrapper.get('[role="dialog"]').text()).toContain(expectedSchedule);
    expect(dispatch).not.toHaveBeenCalledWith(
      'emailCampaigns/schedule',
      expect.anything()
    );
  }
);
