import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CampaignImportsAPI from 'dashboard/api/campaignImports';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/campaignImport.json';

const imports = vi.hoisted(() => ({}));
vi.mock('dashboard/composables/store', async () => {
  const { computed, ref: vueRef } = await import('vue');
  imports.list = vueRef([]);
  return {
    useStore: () => ({ dispatch: vi.fn(() => Promise.resolve()) }),
    useMapGetter: key =>
      computed(() => {
        if (key === 'campaignImports/getCampaignImports')
          return imports.list.value;
        if (key === 'campaignImports/getUIFlags') return {};
        return {};
      }),
  };
});
vi.mock('dashboard/api/campaignImports', () => ({
  default: { download: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: vueRef } = await import('vue');
  return { useCanManage: () => vueRef(true) };
});
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

const { default: CampaignImportHistory } = await import(
  '../CampaignImportHistory.vue'
);

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const ButtonStub = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

const mountPage = () => {
  imports.list.value = [
    {
      id: 5,
      status: 'completed',
      batch_count: 1,
      downloads: { normalized_csv: true },
    },
  ];
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } });
  return mount(CampaignImportHistory, {
    global: {
      plugins: [i18n],
      stubs: { Button: ButtonStub, Dialog: true, Spinner: true },
    },
  });
};

const normalizedButton = wrapper =>
  wrapper
    .findAll('button')
    .find(button => button.text() === en.CAMPAIGN_IMPORT.DOWNLOADS.NORMALIZED);

describe('CampaignImportHistory download (#2802)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('tells who cannot see contacts why the file did not download', async () => {
    CampaignImportsAPI.download.mockRejectedValue({
      response: { status: 403 },
    });
    const wrapper = mountPage();
    await flushPromises();

    await normalizedButton(wrapper).trigger('click');
    await flushPromises();

    expect(CampaignImportsAPI.download).toHaveBeenCalledWith(
      5,
      'normalized_csv'
    );
    expect(useAlert).toHaveBeenCalledWith(
      en.CAMPAIGN_IMPORT.API.DOWNLOAD_HIDDEN
    );
  });

  it('keeps the generic message for any other failure', async () => {
    CampaignImportsAPI.download.mockRejectedValue({
      response: { status: 500 },
    });
    const wrapper = mountPage();
    await flushPromises();

    await normalizedButton(wrapper).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      en.CAMPAIGN_IMPORT.API.DOWNLOAD_ERROR
    );
  });
});
