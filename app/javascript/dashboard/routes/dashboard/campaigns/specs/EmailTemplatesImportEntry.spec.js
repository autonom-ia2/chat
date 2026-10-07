import { ref } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import EmailTemplatesPage from '../pages/EmailTemplatesPage.vue';

const apiIndex = vi.hoisted(() => vi.fn());
const apiShow = vi.hoisted(() => vi.fn());
const latest = vi.hoisted(() => vi.fn());
const compile = vi.hoisted(() => vi.fn());
const routerPush = vi.hoisted(() => vi.fn());
const alert = vi.hoisted(() => vi.fn());
const flags = vi.hoisted(() => ({ on: false, asked: [] }));
const route = vi.hoisted(() => ({ params: { accountId: '800' }, query: {} }));

vi.mock('dashboard/api/emailCampaignTemplates', () => ({
  default: { index: apiIndex, show: apiShow },
}));
vi.mock('dashboard/api/emailCampaignTemplateImports', () => ({
  default: { latest },
}));
vi.mock('dashboard/helper/compileEmailMjml', () => ({
  compileEmailMjml: compile,
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue({}) }),
  useMapGetter: () =>
    ref((accountId, flag) => {
      flags.asked.push([accountId, flag]);
      return flags.on;
    }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(true),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push: routerPush }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const own = {
  id: 55,
  account_id: 800,
  name: 'Novidades de outubro',
  category: 'meus-modelos',
};
const global = {
  id: 1,
  account_id: null,
  name: 'Carrinho',
  catalog_key: 'cart',
  category: 'cart',
};
const defaultPlugins = config.global.plugins;
let wrapper;

beforeAll(() => {
  config.global.plugins = [];
});

afterAll(() => {
  config.global.plugins = defaultPlugins;
});

beforeEach(() => {
  flags.on = false;
  flags.asked = [];
  route.query = {};
  apiIndex.mockResolvedValue({ data: [global, own] });
  apiShow.mockResolvedValue({
    data: { ...own, body_mjml: '<mjml></mjml>', body_html: '' },
  });
  latest.mockResolvedValue({ data: { payload: [] } });
  compile.mockResolvedValue('<html>compilado</html>');
  routerPush.mockReset();
  alert.mockReset();
  vi.stubGlobal(
    'IntersectionObserver',
    class IntersectionObserverStub {
      constructor(callback) {
        this.callback = callback;
      }

      observe(target) {
        this.callback([{ isIntersecting: true, target }]);
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
  wrapper?.unmount();
  vi.unstubAllGlobals();
});

const mountPage = async () => {
  wrapper = mount(EmailTemplatesPage, {
    global: {
      stubs: {
        EmailCampaignDialog: true,
        Dialog: true,
        Spinner: { template: '<span data-spinner />' },
      },
    },
  });
  await flushPromises();
};

const importButtons = () =>
  wrapper
    .findAll('button')
    .filter(button =>
      button.text().includes('EMAIL_IMPORT.SCREEN.LIBRARY.BUTTON')
    );

it('hides "Trazer meu modelo" while the account does not have the flag', async () => {
  await mountPage();

  expect(flags.asked).toContainEqual([800, 'email_template_import']);
  expect(importButtons()).toHaveLength(0);
  expect(latest).not.toHaveBeenCalled();
});

it('opens the import from the library and from an empty "Meus modelos"', async () => {
  flags.on = true;
  apiIndex.mockResolvedValue({ data: [global] });
  await mountPage();

  expect(importButtons()).toHaveLength(1);
  await wrapper.findAll('nav button')[1].trigger('click');
  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.LIBRARY.EMPTY_TITLE');
  expect(importButtons()).toHaveLength(2);

  await importButtons()[1].trigger('click');
  expect(routerPush).toHaveBeenCalledWith({
    name: 'campaigns_email_template_import',
    params: { accountId: '800', importId: undefined },
    query: {},
  });
});

it('marks the model just saved as new, first in "Meus modelos", with its compiled picture', async () => {
  flags.on = true;
  route.query = { novo: '55' };
  await mountPage();

  expect(alert).toHaveBeenCalledWith('EMAIL_IMPORT.SCREEN.LIBRARY.SAVED');
  const card = wrapper.find('article');
  expect(card.attributes('data-template-id')).toBe('55');
  expect(card.text()).toContain('EMAIL_IMPORT.SCREEN.LIBRARY.NEW_BADGE');
  expect(card.text()).toContain('EMAIL_IMPORT.SCREEN.LIBRARY.NEW_HINT');
  expect(compile).toHaveBeenCalledWith('<mjml></mjml>');
  expect(card.find('iframe').attributes('srcdoc')).toBe(
    '<html>compilado</html>'
  );
  expect(card.find('iframe').attributes('sandbox')).toBe('');
});

it('brings back an import that is waiting to be seen', async () => {
  flags.on = true;
  latest.mockResolvedValue({
    data: { payload: [{ id: 12, status: 'ready' }] },
  });
  await mountPage();

  expect(wrapper.text()).toContain('EMAIL_IMPORT.SCREEN.LIBRARY.READY_TITLE');
  const resume = wrapper
    .findAll('button')
    .find(button => button.text().includes('LIBRARY.RESUME'));
  await resume.trigger('click');
  expect(routerPush).toHaveBeenCalledWith(
    expect.objectContaining({
      name: 'campaigns_email_template_import',
      params: { accountId: '800', importId: 12 },
    })
  );
});
