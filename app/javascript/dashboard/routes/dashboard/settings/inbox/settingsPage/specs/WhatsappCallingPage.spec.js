import { mount, flushPromises } from '@vue/test-utils';
import WhatsappCallingPage from '../WhatsappCallingPage.vue';
import CallBusinessHours from '../calls/CallBusinessHours.vue';
import CallAfterCall from '../calls/CallAfterCall.vue';
import InboxesAPI from 'dashboard/api/inboxes';

const { dispatch, alert } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  alert: vi.fn(),
}));

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('dashboard/api/inboxes', () => ({
  default: {
    setInboundCalls: vi.fn(),
    setCallRouting: vi.fn(),
    setCallRecording: vi.fn(),
    enableWhatsappCalling: vi.fn(),
    disableWhatsappCalling: vi.fn(),
    getWhatsappCallHours: vi.fn(),
    applyWhatsappCallHours: vi.fn(),
  },
}));

const inbox = {
  id: 52,
  inbound_calls_enabled: true,
  ring_strategy: 'simultaneous',
  ring_step_seconds: 20,
  assignee_rings_first: true,
  business_hours_calls_enabled: false,
  working_hours_enabled: true,
  timezone: 'America/Los_Angeles',
  working_hours: [
    {
      day_of_week: 1,
      closed_all_day: false,
      open_all_day: false,
      open_hour: 9,
      open_minutes: 0,
      close_hour: 17,
      close_minutes: 0,
    },
  ],
  call_cooldown_seconds: 0,
  recording_enabled: true,
  transcription_enabled: true,
  provider_config: { calling_enabled: true, call_permission_request_body: '' },
};

const mountPage = (overrides = {}) =>
  mount(WhatsappCallingPage, {
    props: { inbox: { ...inbox, ...overrides } },
    global: { stubs: { Icon: true, Spinner: true } },
  });

const saveButton = wrapper => wrapper.findAll('button').at(-1);

describe('WhatsappCallingPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.values(InboxesAPI).forEach(fn => fn.mockResolvedValue({}));
    dispatch.mockResolvedValue({});
  });

  it('shows no greeting or missed-call message, which WhatsApp calls cannot play', () => {
    const wrapper = mountPage();

    expect(wrapper.find('#call-greeting-52').exists()).toBe(false);
    expect(wrapper.find('#call-missed-message-52').exists()).toBe(false);
  });

  it('keeps calling off once turned off, even if refreshing the inbox fails', async () => {
    dispatch.mockRejectedValue(new Error('offline'));
    const wrapper = mountPage();

    await wrapper.findAll('button').at(0).trigger('click');
    await flushPromises();

    expect(alert).toHaveBeenCalledWith('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE');
    expect(wrapper.find('#call-routing-sequential-52').exists()).toBe(false);
  });

  it('saves the permission message', async () => {
    const wrapper = mountPage();
    await wrapper
      .find('#call-permission-request-52')
      .setValue(' Can we call? ');
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 52,
      formData: false,
      channel: {
        provider_config: {
          ...inbox.provider_config,
          call_permission_request_body: 'Can we call?',
        },
      },
    });
    expect(InboxesAPI.setCallRouting).not.toHaveBeenCalled();
  });

  it('turns WhatsApp calling off straight away', async () => {
    const wrapper = mountPage();
    await wrapper.findAll('button').at(0).trigger('click');
    await flushPromises();

    expect(InboxesAPI.disableWhatsappCalling).toHaveBeenCalledWith(52);
  });

  it("explains why calling couldn't be turned on when WhatsApp refuses the hours", async () => {
    InboxesAPI.enableWhatsappCalling.mockRejectedValue({
      response: { data: { message: 'Invalid timezone_id' } },
    });
    const wrapper = mountPage({ provider_config: { calling_enabled: false } });

    await wrapper.find('input[type="checkbox"]').setValue(true);
    await flushPromises();

    expect(alert).toHaveBeenCalledWith('Invalid timezone_id');
  });

  it('only offers to turn calling on while it is off', () => {
    const wrapper = mountPage({ provider_config: { calling_enabled: false } });

    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(1);
    expect(wrapper.findAll('button')).toHaveLength(0);
  });

  // Fork (upgrade 4.20.1, #3120): a WhatsApp call rings as on the fork (Inbox#rings_for_calls? is Twilio only), so the
  // page leaves out who rings, business hours (and their check with WhatsApp) and wrap-up.
  it('leaves who rings, business hours and wrap-up off the page and never checks the call hours', async () => {
    const wrapper = mountPage({ business_hours_calls_enabled: true });
    await flushPromises();

    expect(wrapper.find('#call-routing-sequential-52').exists()).toBe(false);
    expect(wrapper.findComponent(CallBusinessHours).exists()).toBe(false);
    expect(wrapper.findComponent(CallAfterCall).props('showWrapUp')).toBe(
      false
    );
    expect(InboxesAPI.getWhatsappCallHours).not.toHaveBeenCalled();
  });

  it('can save again when refreshing the inbox fails', async () => {
    dispatch.mockRejectedValue(new Error('offline'));
    const wrapper = mountPage();

    await wrapper
      .findComponent(CallAfterCall)
      .vm.$emit('update:recordingEnabled', false);
    await saveButton(wrapper).trigger('click');
    await flushPromises();
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(InboxesAPI.setCallRecording).toHaveBeenCalledTimes(2);
  });

  it('saves the permission message before the call settings, so its whole provider_config does not overwrite them', async () => {
    const wrapper = mountPage();
    await wrapper
      .findComponent(CallAfterCall)
      .vm.$emit('update:recordingEnabled', false);
    await wrapper.find('#call-permission-request-52').setValue('Can we call?');
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    const updateInboxOrder =
      dispatch.mock.invocationCallOrder[
        dispatch.mock.calls.findIndex(
          ([action]) => action === 'inboxes/updateInbox'
        )
      ];
    const [recordingOrder] =
      InboxesAPI.setCallRecording.mock.invocationCallOrder;
    expect(updateInboxOrder).toBeLessThan(recordingOrder);
    expect(InboxesAPI.setCallRouting).not.toHaveBeenCalled();
  });
});
