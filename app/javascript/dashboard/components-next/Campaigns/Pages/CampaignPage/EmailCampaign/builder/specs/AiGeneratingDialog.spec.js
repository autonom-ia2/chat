import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaign.json';

const status = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/emailCampaignAi', () => ({ default: { status } }));

const { default: AiGeneratingDialog } = await import(
  '../AiGeneratingDialog.vue'
);

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  vi.clearAllMocks();
});

const POLL_MS = 4000;

const mountDialog = mode =>
  mount(AiGeneratingDialog, {
    props: { campaignId: 7, mode },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

const pollOnce = async () => {
  vi.advanceTimersByTime(POLL_MS);
  await flushPromises();
};

// #1095: an adjustment goes straight to the before/after; a failure says why in one sentence.
describe('AiGeneratingDialog in adjust mode', () => {
  it('talks about adjusting and hands the proposal over when ready', async () => {
    const data = {
      ai_status: 'ready',
      ai_adjustment: { status: 'proposed', base: 'a', mjml: 'b' },
    };
    status.mockResolvedValue({ data });
    const wrapper = mountDialog('adjust');

    expect(wrapper.text()).toContain('Adjusting your email');
    await pollOnce();

    expect(wrapper.emitted('ready')).toEqual([[data]]);
  });

  it("shows the model's sentence when the request cannot be done", async () => {
    status.mockResolvedValue({
      data: {
        ai_status: 'failed',
        ai_error: 'adjust_refused',
        ai_adjustment: {
          status: 'refused',
          reason: 'Video does not play inside an email.',
        },
      },
    });
    const wrapper = mountDialog('adjust');
    await pollOnce();

    expect(wrapper.text()).toContain("I couldn't make this change");
    expect(wrapper.text()).toContain('Video does not play inside an email.');
  });

  it('says in plain words which quality rule the change would break', async () => {
    status.mockResolvedValue({
      data: {
        ai_status: 'failed',
        ai_error: 'adjust_quality',
        ai_adjustment: { status: 'failed', problem: 'contrast' },
      },
    });
    const wrapper = mountDialog('adjust');
    await pollOnce();

    expect(wrapper.text()).toContain(
      'The change would make the text hard to read, so your email stayed as it was.'
    );
  });

  it('recognises an adjustment resumed after leaving the page', async () => {
    const data = { ai_status: 'ready', ai_adjustment: { status: 'proposed' } };
    status.mockResolvedValue({ data });
    const wrapper = mountDialog();
    await pollOnce();

    expect(wrapper.emitted('ready')).toEqual([[data]]);
  });
});
