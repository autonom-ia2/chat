import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaign.json';

const generate = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/emailCampaignAi', () => ({ default: { generate } }));
vi.mock('dashboard/api/emailCampaignAssets', () => ({ default: {} }));
// Visual identity (#1076) off unless a case turns it on; BrandIdentityChoices.spec covers the picker.
const brandKitsEnabled = vi.hoisted(() => ({ value: false }));
const brandKitsList = vi.hoisted(() => [
  { id: 1, name: 'Hub2You', is_default: true },
  { id: 2, name: 'Autonomia', is_default: false },
  { id: 3, name: 'Aurora', is_default: false },
]);
// The list the dialog sees; a case may empty it and fill it after mount (the kits load late).
const loadedKits = vi.hoisted(() => ({ ref: null }));
vi.mock('dashboard/components-next/BrandKits/useBrandKits', async () => {
  const { ref } = await import('vue');
  loadedKits.ref = ref(brandKitsList);
  return {
    useBrandKits: () => ({
      isEnabled: ref(brandKitsEnabled.value),
      kits: loadedKits.ref,
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
afterEach(() => {
  vi.clearAllMocks();
  brandKitsEnabled.value = false;
});

const mountDialog = props =>
  mount(AiComposerDialog, {
    props: { campaignId: 7, placeholders: ['nome', 'contact.email'], ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { BrandIdentityPicker: true },
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

  // #1076 + #1095: the identity chosen for the e-mail goes with an adjustment too.
  it('sends the chosen visual identity together with the e-mail to adjust', async () => {
    brandKitsEnabled.value = true;
    generate.mockResolvedValue({});
    const wrapper = mountDialog({
      canAdjust: true,
      readCurrentMjml: () => '<mjml>screen</mjml>',
      initialBrand: { kitId: 3, mode: 'dark' },
    });
    await typeRequest(wrapper, 'Use as cores da marca no botão');

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(generate).toHaveBeenCalledWith(
      expect.objectContaining({
        baseMjml: '<mjml>screen</mjml>',
        brand: { brand_kit_id: 3, brand_mode: 'dark' },
      })
    );
  });
});

// #1126: "Trocar" in the editor's identity panel opens the dialog with the identity picked and the request
// already written; the person may edit it. Empty canvas: "Criar com IA" with the identity picked.
describe('AiComposerDialog — identity picked in the editor panel (#1126)', () => {
  const changeIdentity = { kitId: 2, name: 'Autonomia' };
  const request = name =>
    `Apply the ${name} identity to the whole email: colors, fonts and logo.`;
  const brief = wrapper =>
    wrapper.find('[data-test="ai-composer-brief"] textarea');
  const picker = wrapper =>
    wrapper.findComponent({ name: 'BrandIdentityPicker' });

  beforeEach(() => {
    brandKitsEnabled.value = true;
  });

  it('adjusts with the identity picked and the request written, and sends what the person edited', async () => {
    generate.mockResolvedValue({});
    const wrapper = mountDialog({
      canAdjust: true,
      readCurrentMjml: () => '<mjml>screen</mjml>',
      initialBrand: { kitId: 1, mode: 'dark' },
      changeIdentity,
    });

    expect(title(wrapper)).toBe('Adjust with AI');
    expect(brief(wrapper).element.value).toBe(request('Autonomia'));
    expect(picker(wrapper).props('modelValue')).toMatchObject({
      kitId: 2,
      mode: 'dark',
    });

    await typeRequest(wrapper, `${request('Autonomia')} Keep the photos.`);
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(generate).toHaveBeenCalledWith(
      expect.objectContaining({
        brief: `${request('Autonomia')} Keep the photos.`,
        baseMjml: '<mjml>screen</mjml>',
        brand: { brand_kit_id: 2, brand_mode: 'dark' },
      })
    );
    expect(wrapper.emitted('generationStarted')).toEqual([
      [{ mode: 'adjust' }],
    ]);
  });

  it('follows another identity picked in the dialog while the request is untouched', async () => {
    const wrapper = mountDialog({ canAdjust: true, changeIdentity });

    picker(wrapper).vm.$emit('update:modelValue', {
      ...picker(wrapper).props('modelValue'),
      kitId: 3,
    });
    await flushPromises();
    expect(brief(wrapper).element.value).toBe(request('Aurora'));

    await typeRequest(wrapper, 'Only the button');
    picker(wrapper).vm.$emit('update:modelValue', {
      ...picker(wrapper).props('modelValue'),
      kitId: 1,
    });
    await flushPromises();
    expect(brief(wrapper).element.value).toBe('Only the button');
  });

  it('leaves the request empty when the person chooses to create a new e-mail instead', async () => {
    const wrapper = mountDialog({ canAdjust: true, changeIdentity });

    await wrapper
      .find('[data-test="ai-composer-adjust-only"] input')
      .setValue(false);
    expect(brief(wrapper).element.value).toBe('');

    await wrapper
      .find('[data-test="ai-composer-adjust-only"] input')
      .setValue(true);
    expect(brief(wrapper).element.value).toBe(request('Autonomia'));
  });

  describe('when the identities load after the dialog opened', () => {
    beforeEach(() => {
      loadedKits.ref.value = [];
    });
    afterEach(() => {
      loadedKits.ref.value = brandKitsList;
    });

    const pickAurora = async wrapper => {
      picker(wrapper).vm.$emit('update:modelValue', {
        ...picker(wrapper).props('modelValue'),
        kitId: 3,
      });
      await flushPromises();
    };

    it('writes the request once the name of the identity picked is known', async () => {
      const wrapper = mountDialog({ canAdjust: true, changeIdentity });
      await pickAurora(wrapper);
      expect(brief(wrapper).element.value).toBe('');

      loadedKits.ref.value = brandKitsList;
      await flushPromises();

      expect(brief(wrapper).element.value).toBe(request('Aurora'));
    });

    it('never overwrites what the person typed before they loaded', async () => {
      const wrapper = mountDialog({ canAdjust: true, changeIdentity });
      await pickAurora(wrapper);
      await typeRequest(wrapper, 'Só o botão');

      loadedKits.ref.value = brandKitsList;
      await flushPromises();

      expect(brief(wrapper).element.value).toBe('Só o botão');
    });
  });

  it('opens "Create with AI" with the identity picked when the canvas is empty', () => {
    const wrapper = mountDialog({ changeIdentity });

    expect(title(wrapper)).toBe('Create with AI');
    expect(brief(wrapper).element.value).toBe('');
    expect(picker(wrapper).props('modelValue')).toMatchObject({ kitId: 2 });
  });
});
