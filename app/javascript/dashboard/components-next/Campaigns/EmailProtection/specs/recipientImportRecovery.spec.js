import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import recoveryEn from 'dashboard/i18n/locale/en/emailCampaignImportRecovery.json';
import RecipientImportRecoveryDialog from '../../Pages/CampaignPage/EmailCampaign/RecipientImportRecoveryDialog.vue';

const dispatch = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => ref(false),
}));
const plugins = config.global.plugins;
const originalShowModal = HTMLDialogElement.prototype.showModal;
const closeDialog = HTMLDialogElement.prototype.close;
const text = recoveryEn.EMAIL_CAMPAIGN_IMPORT_RECOVERY;
const campaign = {
  id: 50,
  status: 'draft',
  body_html: '<p>Saved draft</p>',
  recipient_import: {
    id: 28,
    status: 'failed',
    retryable: true,
    error_code: 'schema_not_resolved',
  },
};
const options = {
  props: { campaign },
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: recoveryEn },
      }),
    ],
    stubs: { teleport: true },
  },
};
let wrapper;
beforeAll(() => {
  config.global.plugins = [];
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
  };
});
afterAll(() => {
  config.global.plugins = plugins;
  HTMLDialogElement.prototype.showModal = originalShowModal;
  HTMLDialogElement.prototype.close = closeDialog;
});
beforeEach(() => {
  dispatch.mockReset();
});
afterEach(() => {
  wrapper?.unmount();
});

it('shows the known reason, correction and uploads the replacement to the same campaign', async () => {
  wrapper = mount(RecipientImportRecoveryDialog, options);
  wrapper.vm.open();
  await flushPromises();
  expect(wrapper.text()).toContain(text.CAUSES.AMBIGUOUS.REASON);
  expect(wrapper.text()).toContain(text.CAUSES.AMBIGUOUS.CORRECTION);
  expect(wrapper.text()).not.toContain(text.RETRY);
  const upload = wrapper
    .findAll('button')
    .find(button => button.text() === text.UPLOAD);
  expect(upload.attributes('disabled')).toBeDefined();
  const file = new File(['Nome,Email\nAna,ana@example.test'], 'corrected.csv', {
    type: 'text/csv',
  });
  Object.defineProperty(wrapper.get('input').element, 'files', {
    value: [file],
  });
  await wrapper.get('input').trigger('change');
  await upload.trigger('click');
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith('emailCampaigns/importRecipients', {
    id: 50,
    file,
  });
  expect(campaign.body_html).toBe('<p>Saved draft</p>');
  expect(wrapper.get('dialog').element.open).toBe(false);
});

it('offers original-file retry for a temporary service failure', async () => {
  wrapper = mount(RecipientImportRecoveryDialog, {
    ...options,
    props: {
      campaign: {
        ...campaign,
        recipient_import: {
          ...campaign.recipient_import,
          error_code: 'typesafe_unavailable',
        },
      },
    },
  });
  wrapper.vm.open();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === text.RETRY)
    .trigger('click');
  expect(dispatch).toHaveBeenCalledWith('emailCampaigns/retryImport', 50);
});

it('keeps a failed upload actionable inside the dialog without displaying raw server errors', async () => {
  dispatch.mockRejectedValue({
    response: {
      data: { error: 'file_expired', message: 'private internal detail' },
    },
  });
  wrapper = mount(RecipientImportRecoveryDialog, {
    ...options,
    props: {
      campaign: {
        ...campaign,
        recipient_import: {
          ...campaign.recipient_import,
          error_code: 'typesafe_unavailable',
        },
      },
    },
  });
  wrapper.vm.open();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === text.RETRY)
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(text.CAUSES.EXPIRED.REASON);
  expect(wrapper.text()).not.toContain('private internal detail');
  expect(wrapper.get('dialog').element.open).toBe(true);
});
