import { shallowMount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import ClientErrorsAPI from 'dashboard/api/clientErrors';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/campaign.json';

const editor = vi.hoisted(() => ({}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/composables/useEmailEditor',
  () => ({ useEmailEditor: () => editor.api })
);
const dispatch = vi.hoisted(() => vi.fn(() => Promise.resolve({})));
const campaigns = vi.hoisted(() => ({}));
vi.mock('dashboard/composables/store', async () => {
  const { computed, ref: vueRef } = await import('vue');
  campaigns.list = vueRef([]);
  return {
    useStore: () => ({ dispatch }),
    useMapGetter: key =>
      computed(() => {
        if (key === 'emailCampaigns/getCampaigns') return campaigns.list.value;
        if (key === 'emailCampaigns/getUIFlags') return {};
        return { email: 'gestora@empresa.com.br' };
      }),
  };
});
vi.mock('dashboard/api/clientErrors', () => ({
  default: { report: vi.fn(() => Promise.resolve()) },
}));
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
  campaigns.list.value = [
    { id: 7, name: 'Outubro', body_mjml: '<mjml></mjml>' },
  ];
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

const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);

const serverError = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status },
  });

let consoleError;
beforeEach(() => {
  consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.clearAllMocks();
  dispatch.mockImplementation(() => Promise.resolve({}));
});

// #1824: the save used to swallow the real error; the 13/10 failure (account 17) left no trace.
describe('EmailBuilderPage — failed save', () => {
  it('keeps the real error when the editor export throws before the request', async () => {
    const failure = new Error('export failed');
    const wrapper = mountWith(
      vi.fn(() => {
        throw failure;
      })
    );

    await button(wrapper, 'Save').trigger('click');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'emailCampaigns/update',
      expect.anything()
    );
    expect(consoleError).toHaveBeenCalledWith(
      '[EmailBuilderPage] save failed',
      '',
      failure.stack
    );
    expect(ClientErrorsAPI.report).toHaveBeenCalledWith({
      flow: 'email_builder_save',
      error: failure,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Could not save the campaign, try again'
    );
  });

  it('still shows the alert when even logging the error fails', async () => {
    const wrapper = mountWith(
      vi.fn(() => {
        throw Object.create(null);
      })
    );

    await button(wrapper, 'Save').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Could not save the campaign, try again'
    );
  });

  it('logs a refused save (422) without reporting it to the server', async () => {
    dispatch.mockImplementation(() => Promise.reject(serverError(422)));
    const wrapper = mountWith(vi.fn(() => '<mjml></mjml>'));

    await button(wrapper, 'Save').trigger('click');
    await flushPromises();

    expect(consoleError).toHaveBeenCalledWith(
      '[EmailBuilderPage] save failed',
      422,
      expect.stringContaining('status code 422')
    );
    expect(ClientErrorsAPI.report).not.toHaveBeenCalled();
  });

  it('reports a server failure from "Review and send" and stays on the editor', async () => {
    const failure = serverError(500);
    dispatch.mockImplementation(() => Promise.reject(failure));
    const wrapper = mountWith(vi.fn(() => '<mjml></mjml>'));

    await button(wrapper, 'Review and send').trigger('click');
    await flushPromises();

    expect(ClientErrorsAPI.report).toHaveBeenCalledWith({
      flow: 'email_builder_save',
      error: failure,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Could not save the campaign, try again'
    );
  });
});

// #2545: a draft without a subject comes from the server as null. Save used to break on null.trim().
describe('EmailBuilderPage — campaign without a subject', () => {
  const loadWithoutSubject = async wrapper => {
    campaigns.list.value = [
      { id: 7, name: 'Outubro', body_mjml: '<mjml></mjml>', subject: null },
    ];
    await wrapper.vm.$nextTick();
  };

  it('saves the draft with an empty subject', async () => {
    const wrapper = mountWith(vi.fn(() => '<mjml></mjml>'));
    await loadWithoutSubject(wrapper);

    await button(wrapper, 'Save').trigger('click');
    await flushPromises();

    expect(consoleError).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith(
      'emailCampaigns/update',
      expect.objectContaining({ id: 7, subject: '' })
    );
    expect(useAlert).toHaveBeenCalledWith('Campaign saved successfully');
  });

  it('goes to "Review and send" without breaking', async () => {
    const wrapper = mountWith(vi.fn(() => '<mjml></mjml>'));
    await loadWithoutSubject(wrapper);

    await button(wrapper, 'Review and send').trigger('click');
    await flushPromises();

    expect(consoleError).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith(
      'emailCampaigns/update',
      expect.objectContaining({ id: 7, subject: '' })
    );
  });

  it('asks for the subject before a test send and opens Email details', async () => {
    const wrapper = mountWith(vi.fn(() => '<mjml></mjml>'));
    await loadWithoutSubject(wrapper);

    await wrapper.find('button[aria-label="Send test"]').trigger('click');
    wrapper
      .findComponent({ name: 'TestSendForm' })
      .vm.$emit('send', ['gestora@empresa.com.br']);
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'emailCampaigns/sendTest',
      expect.anything()
    );
    expect(
      wrapper.findComponent({ name: 'TestSendForm' }).props('errorMessage')
    ).toBe('Add the subject in Email details.');
    expect(
      wrapper
        .find('button[aria-label="Email details"]')
        .attributes('aria-expanded')
    ).toBe('true');
  });
});
