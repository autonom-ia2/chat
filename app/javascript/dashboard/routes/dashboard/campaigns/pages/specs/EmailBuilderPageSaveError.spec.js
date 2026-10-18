import { shallowMount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import * as Sentry from '@sentry/vue';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/campaign.json';

const editor = vi.hoisted(() => ({}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/composables/useEmailEditor',
  () => ({ useEmailEditor: () => editor.api })
);
const dispatch = vi.hoisted(() => vi.fn(() => Promise.resolve({})));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch }),
    useMapGetter: key =>
      computed(() => {
        if (key === 'emailCampaigns/getCampaigns')
          return [{ id: 7, name: 'Outubro', body_mjml: '<mjml></mjml>' }];
        if (key === 'emailCampaigns/getUIFlags') return {};
        return { email: 'gestora@empresa.com.br' };
      }),
  };
});
vi.mock('@sentry/vue', () => ({ captureException: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: vueRef } = await import('vue');
  return { useCanManage: () => vueRef(true) };
});
vi.mock('dashboard/composables/useRecipientImportPolling', () => ({
  useRecipientImportPolling: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, campaignId: 7 }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('dashboard/api/emailCampaignAi', () => ({
  default: { status: vi.fn() },
}));
vi.mock('dashboard/api/emailCampaignTemplates', () => ({ default: {} }));
vi.mock('dashboard/components-next/BrandKits/useBrandKits', async () => {
  const { ref: vueRef } = await import('vue');
  return { useBrandKits: () => ({ isEnabled: vueRef(false) }) };
});

const { default: EmailBuilderPage } = await import('../EmailBuilderPage.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const mountWith = getMjml => {
  editor.api = {
    isReady: ref(true),
    device: ref('desktop'),
    contentVersion: ref(0),
    selectedComponent: ref(null),
    isTextSelected: ref(false),
    getMjml,
    getHtml: vi.fn(() => '<html></html>'),
    setMjml: vi.fn(),
    compileMjml: vi.fn(() => '<html></html>'),
    setDevice: vi.fn(),
    setSelectedText: vi.fn(),
    adjustCanvasScroll: vi.fn(),
    setCanvasPreview: vi.fn(),
  };
  return shallowMount(EmailBuilderPage, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Button: false },
    },
  });
};

const saveButton = wrapper =>
  wrapper.findAll('button').find(button => button.text() === 'Save');

afterEach(() => vi.clearAllMocks());

// #1824: the save used to swallow the real error; the 13/10 failure (account 17) left no trace.
describe('EmailBuilderPage — failed save', () => {
  it('keeps the real error when the editor export throws before the request', async () => {
    const failure = new Error('export failed');
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {});
    const wrapper = mountWith(
      vi.fn(() => {
        throw failure;
      })
    );

    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'emailCampaigns/update',
      expect.anything()
    );
    expect(consoleError).toHaveBeenCalledWith(
      '[EmailBuilderPage] save failed',
      failure
    );
    expect(Sentry.captureException).toHaveBeenCalledWith(failure);
    expect(useAlert).toHaveBeenCalledWith(
      'Could not save the campaign, try again'
    );
    consoleError.mockRestore();
  });
});
