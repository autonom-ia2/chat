import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaign.json';

const generate = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/emailCampaignAi', () => ({ default: { generate } }));
vi.mock('dashboard/api/emailCampaignAssets', () => ({ default: {} }));
// Visual identity (#1076) off: these cases are about adjusting; BrandIdentityChoices.spec covers the picker.
vi.mock('dashboard/components-next/BrandKits/useBrandKits', async () => {
  const { ref } = await import('vue');
  return {
    useBrandKits: () => ({
      isEnabled: ref(false),
      kits: ref([]),
      fetchKits: vi.fn(),
    }),
  };
});

const { default: AiComposerDialog } = await import('../AiComposerDialog.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});
afterEach(() => vi.clearAllMocks());

const mountDialog = props =>
  mount(AiComposerDialog, {
    props: { campaignId: 7, placeholders: ['nome', 'contact.email'], ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

const title = wrapper => wrapper.find('[data-test="ai-composer-title"]').text();
const submit = wrapper => wrapper.find('[data-test="ai-composer-submit"]');
const typeRequest = (wrapper, value) =>
  wrapper.find('[data-test="ai-composer-brief"] textarea').setValue(value);

// #1095: with content on the canvas the dialog adjusts it; empty, it creates a new e-mail.
describe('AiComposerDialog', () => {
  it('creates from scratch when the canvas is empty', () => {
    const wrapper = mountDialog();

    expect(title(wrapper)).toBe('Create with AI');
    expect(wrapper.text()).toContain('Briefing');
    expect(submit(wrapper).text()).toBe('Generate');
    expect(wrapper.find('[data-test="ai-composer-adjust-only"]').exists()).toBe(
      false
    );
  });

  it('speaks of adjusting when the canvas has content', () => {
    const wrapper = mountDialog({ canAdjust: true });

    expect(title(wrapper)).toBe('Adjust with AI');
    expect(wrapper.text()).toContain('What do you want to change?');
    expect(
      wrapper
        .find('[data-test="ai-composer-brief"] textarea')
        .attributes('placeholder')
    ).toBe(
      'E.g.: change the title, make the button green, remove the questions section'
    );
    expect(submit(wrapper).text()).toBe('Adjust');
  });

  it('explains personalization in plain words, without technical fields', () => {
    const wrapper = mountDialog({ canAdjust: true });

    expect(
      wrapper.find('[data-test="ai-composer-personalize"]').text()
    ).toContain('start with the person');
    expect(wrapper.text()).not.toContain('{{');
  });

  it('sends the canvas as it is when the person submits, with the request verbatim', async () => {
    generate.mockResolvedValue({});
    let canvas = '<mjml>first</mjml>';
    const wrapper = mountDialog({
      canAdjust: true,
      readCurrentMjml: () => canvas,
    });
    await typeRequest(wrapper, 'Deixe o botão verde');
    canvas = '<mjml>edited, not saved</mjml>';

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(generate).toHaveBeenCalledWith(
      expect.objectContaining({
        campaignId: 7,
        brief: 'Deixe o botão verde',
        baseMjml: '<mjml>edited, not saved</mjml>',
      })
    );
    expect(wrapper.emitted('generationStarted')).toEqual([
      [{ mode: 'adjust' }],
    ]);
  });

  it('creates a new e-mail from scratch when the person unticks "change only what I ask"', async () => {
    generate.mockResolvedValue({});
    const readCurrentMjml = vi.fn(() => '<mjml>screen</mjml>');
    const wrapper = mountDialog({ canAdjust: true, readCurrentMjml });

    await wrapper
      .find('[data-test="ai-composer-adjust-only"] input')
      .setValue(false);
    expect(title(wrapper)).toBe('Create with AI');
    expect(wrapper.text()).toContain(
      'A new email will be created from scratch.'
    );
    await typeRequest(wrapper, 'E-mail de Natal');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(generate.mock.calls[0][0].baseMjml).toBeUndefined();
    expect(readCurrentMjml).not.toHaveBeenCalled();
    expect(wrapper.emitted('generationStarted')).toEqual([
      [{ mode: 'create' }],
    ]);
  });

  it('says plainly when the e-mail is too big to adjust', async () => {
    generate.mockRejectedValue({
      response: { data: { error: 'email_campaign.base_mjml_too_large' } },
    });
    const wrapper = mountDialog({
      canAdjust: true,
      readCurrentMjml: () => 'x',
    });
    await typeRequest(wrapper, 'Troque o título');

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('This email is too big to adjust at once');
  });
});
