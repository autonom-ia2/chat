import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import axios from 'axios';
import CompanyMedia from '../CompanyMedia.vue';

const context = vi.hoisted(() => ({ push: vi.fn(), replace: vi.fn() }));
vi.mock('axios', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => context,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(31) }),
}));
const row = (id, filename) => ({
  id,
  filename,
  byte_size: 1024,
  content_type: 'application/pdf',
  file_type: 'file',
  contact: { id: 4, name: 'Contato sintético' },
  sender: { name: 'Agente sintético' },
  created_at: '2026-09-29T12:00:00Z',
  conversation_id: 22,
  message_id: 33,
});
const response = (rows, total = rows.length) => ({
  data: { payload: rows, meta: { total } },
});
const mountMedia = () =>
  mount(CompanyMedia, {
    props: { companyId: 3, expanded: true },
    global: {
      stubs: {
        MediaThumbnail: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
});

it('sends filename search and grouping to the server and keeps occurrence IDs and origins', async () => {
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [] }
        : response([row(1, 'repetido.pdf'), row(2, 'repetido.pdf')], 26)
    )
  );
  const wrapper = mountMedia();
  await flushPromises();
  expect(wrapper.findAll('tbody tr')).toHaveLength(2);
  expect(wrapper.text()).toContain('Contato sintético');
  expect(wrapper.text()).toContain('Agente sintético');
  await wrapper.find('input[type="search"]').setValue('arquivo-antigo');
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/companies/3/media',
    { params: { q: 'arquivo-antigo', group: 'contact', page: 1, per_page: 25 } }
  );
  const origin = wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.MEDIA.ORIGIN');
  await origin.trigger('click');
  expect(context.push).toHaveBeenCalledWith({
    name: 'inbox_conversation',
    params: { accountId: 31, conversation_id: 22 },
    query: { messageId: 33 },
  });
  wrapper.unmount();
});

it('ignores a late media response after switching companies', async () => {
  let first;
  axios.get.mockImplementation(url => {
    if (url.endsWith('/contacts')) return Promise.resolve({ data: [] });
    if (url.includes('/companies/3/'))
      return new Promise(resolve => {
        first = resolve;
      });
    return Promise.resolve(response([row(8, 'empresa-atual.pdf')]));
  });
  const wrapper = mountMedia();
  await wrapper.setProps({ companyId: 9 });
  await flushPromises();
  first(response([row(7, 'empresa-anterior.pdf')]));
  await flushPromises();
  expect(wrapper.text()).toContain('empresa-atual.pdf');
  expect(wrapper.text()).not.toContain('empresa-anterior.pdf');
  wrapper.unmount();
});

it.each(['unmount', 'company'])(
  'does not open a delayed original after %s',
  async action => {
    axios.get.mockImplementation(url =>
      Promise.resolve(
        url.endsWith('/contacts')
          ? { data: [] }
          : response([row(1, 'report.pdf')])
      )
    );
    const wrapper = mountMedia();
    await flushPromises();
    let reply;
    axios.get.mockImplementation(url =>
      url.endsWith('/1')
        ? new Promise(resolve => {
            reply = resolve;
          })
        : Promise.resolve(
            url.endsWith('/contacts') ? { data: [] } : response([])
          )
    );
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIPS.MEDIA.DOWNLOAD')
      .trigger('click');
    if (action === 'unmount') wrapper.unmount();
    else await wrapper.setProps({ companyId: 4 });
    reply({ data: { url: 'https://example.test/authorized-original' } });
    await flushPromises();
    expect(click).not.toHaveBeenCalled();
    click.mockRestore();
    if (action !== 'unmount') wrapper.unmount();
  }
);

// Match the dashboard bootstrap: feature requests use the configured global client.
const originalDashboardClient = window.axios;
beforeEach(() => {
  window.axios = axios;
});
afterEach(() => {
  window.axios = originalDashboardClient;
});
