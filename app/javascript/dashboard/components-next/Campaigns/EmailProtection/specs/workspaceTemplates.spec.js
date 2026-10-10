import { ref } from 'vue';
import { flushPromises, mount, config } from '@vue/test-utils';
import EmailTemplatesPage from 'dashboard/routes/dashboard/campaigns/pages/EmailTemplatesPage.vue';

const apiIndex = vi.hoisted(() => vi.fn());
const apiShow = vi.hoisted(() => vi.fn());
const dispatch = vi.hoisted(() => vi.fn());
const routerPush = vi.hoisted(() => vi.fn());
const alert = vi.hoisted(() => vi.fn());

vi.mock('dashboard/api/emailCampaignTemplates', () => ({
  default: { index: apiIndex, show: apiShow },
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => ref(() => false),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => true,
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '800' }, query: {} }),
  useRouter: () => ({ push: routerPush }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const template = {
  id: 1,
  account_id: null,
  name: 'Abandoned Cart',
  catalog_key: 'abandoned_cart',
  category: 'abandoned-cart',
};
const fullTemplate = {
  ...template,
  body_mjml: '<mjml><mj-body><mj-text>Hello</mj-text></mj-body></mjml>',
  body_html: '<p>Hello</p>',
};

const defaultPlugins = config.global.plugins;

beforeAll(() => {
  config.global.plugins = [];
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

afterAll(() => {
  config.global.plugins = defaultPlugins;
});

beforeEach(() => {
  apiIndex.mockResolvedValue({ data: [template] });
  apiShow.mockResolvedValue({ data: fullTemplate });
  dispatch.mockResolvedValue({});
  routerPush.mockReset();
  alert.mockReset();
  vi.stubGlobal(
    'IntersectionObserver',
    class IntersectionObserverStub {
      observe() {
        return this;
      }

      unobserve() {
        return this;
      }

      disconnect() {
        return this;
      }
    }
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
});

it('keeps device preview controls inside the dialog without submitting its form', async () => {
  const wrapper = mount(EmailTemplatesPage, {
    global: {
      stubs: {
        EmailCampaignDialog: { template: '<div data-new-template-dialog />' },
        Spinner: { template: '<span data-spinner />' },
      },
    },
  });
  await flushPromises();

  await wrapper.find('article button').trigger('click');
  await flushPromises();

  const mobile = Array.from(
    document.body.querySelectorAll('dialog button')
  ).find(button => button.textContent.includes('DEVICES.mobile'));
  expect(mobile).toBeDefined();
  expect(mobile.getAttribute('type')).toBe('button');

  mobile.click();
  await flushPromises();

  expect(document.body.querySelector('dialog[open]')).not.toBeNull();
  expect(mobile.getAttribute('aria-pressed')).toBe('true');
  expect(wrapper.find('[data-new-template-dialog]').exists()).toBe(false);
  expect(apiShow).toHaveBeenCalledTimes(1);
});
