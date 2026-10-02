import { mount, flushPromises } from '@vue/test-utils';
import { ref, reactive } from 'vue';
import axios from 'axios';
import RelationshipMedia from 'dashboard/components-next/Relationships/RelationshipMedia.vue';

const accountId = ref(31);
const route = reactive({ query: {} });
const routing = vi.hoisted(() => ({
  push: vi.fn(),
  replace: vi.fn(),
  resolve: vi.fn(() => ({ href: '/conversation-origin' })),
}));
vi.mock('axios', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => routing,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
const row = {
  id: 1,
  filename: 'proposta.pdf',
  byte_size: 1024,
  content_type: 'application/pdf',
  file_type: 'file',
  contact: { id: 42, name: 'Mariana' },
  sender: { name: 'Agente' },
  created_at: '2026-09-30T12:00:00Z',
  conversation_id: 22,
  message_id: 33,
};
const mountMedia = (props = {}) =>
  mount(RelationshipMedia, {
    props: { contactId: 42, embedded: true, ...props },
    global: {
      stubs: {
        MediaThumbnail: true,
        teleport: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
const button = (wrapper, text) =>
  wrapper.findAll('button').find(item => item.text() === text);
const dashboardClient = window.axios;
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  accountId.value = 31;
  route.query = {
    card_id: '9',
    pipeline_id: '4',
    media: JSON.stringify({ q: 'unrelated', page: 4 }),
  };
  window.axios = axios;
  Element.prototype.scrollIntoView = vi.fn();
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [] }
        : { data: { payload: [row], meta: { total: 26 } } }
    )
  );
});
afterEach(() => {
  wrapper?.unmount();
  window.axios = dashboardClient;
});

it('starts with a contact-scoped request and does not reuse unrelated route filters', async () => {
  wrapper = mountMedia();
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/contacts/42/media',
    { params: { page: 1, per_page: 5 } }
  );
  expect(routing.replace).not.toHaveBeenCalled();
});
it('searches and paginates via the real contract without modifying the CRM URL', async () => {
  wrapper = mountMedia({ expanded: true });
  await flushPromises();
  await wrapper.find('input[type="search"]').setValue('contrato antigo');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/contacts/42/media',
    { params: { q: 'contrato antigo', page: 1, per_page: 25 } }
  );
  await button(wrapper, 'RELATIONSHIPS.NEXT').trigger('click');
  await flushPromises();
  expect(axios.get.mock.lastCall[1].params.page).toBe(2);
  expect(routing.replace).not.toHaveBeenCalled();
  expect(routing.push).not.toHaveBeenCalled();
  expect(route.query.card_id).toBe('9');
});
it('expands company media in the same drawer rather than navigating away', async () => {
  wrapper = mountMedia({ contactId: null, companyId: 7 });
  await flushPromises();
  await button(wrapper, 'RELATIONSHIPS.MEDIA.ALL').trigger('click');
  expect(wrapper.emitted('expand')).toHaveLength(1);
  expect(routing.push).not.toHaveBeenCalled();
  await wrapper.setProps({ expanded: true });
  await flushPromises();
  expect(wrapper.find('table').exists()).toBe(false);
  expect(wrapper.findAll('[data-media-row]')).toHaveLength(1);
  expect(axios.get.mock.lastCall[1].params.per_page).toBe(25);
});
it('opens the conversation in another tab and marks contact links similarly', async () => {
  const open = vi.spyOn(window, 'open').mockImplementation(() => null);
  wrapper = mountMedia();
  await flushPromises();
  await wrapper.vm.openOrigin(row);
  expect(open).toHaveBeenCalledWith(
    '/conversation-origin',
    '_blank',
    'noopener,noreferrer'
  );
  expect(routing.push).not.toHaveBeenCalled();
  expect(wrapper.find('a').attributes('target')).toBe('_blank');
  open.mockRestore();
});
it('renders company groups in the compact layout without a wide table', async () => {
  wrapper = mountMedia({ contactId: null, companyId: 7, expanded: true });
  await flushPromises();
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('[data-media-group]').text()).toBe('Mariana');
  expect(axios.get.mock.lastCall[1].params.group).toBe('contact');
});
it('never shows an old contact media response after switching context', async () => {
  let resolve;
  axios.get.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  wrapper = mountMedia();
  await wrapper.setProps({ contactId: 43 });
  await flushPromises();
  resolve({
    data: {
      payload: [{ ...row, filename: 'previous-contact.pdf' }],
      meta: { total: 1 },
    },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('previous-contact.pdf');
});
it('does not silently convert a forbidden request to an empty gallery', async () => {
  axios.get.mockRejectedValue({ response: { status: 403 } });
  wrapper = mountMedia();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toContain(
    'RELATIONSHIPS.MEDIA.LOAD_ERROR'
  );
  expect(wrapper.findAll('[data-media-row]')).toHaveLength(0);
});
