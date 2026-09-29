import { flushPromises, mount } from '@vue/test-utils';
import { ref, reactive } from 'vue';
import axios from 'axios';
import CompanyMediaView from 'dashboard/routes/dashboard/relationships/CompanyMediaView.vue';

const accountId = ref(31);
const mediaEnabled = ref(true);
const route = reactive({ params: { companyId: '3' }, query: {} });
vi.mock('axios', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({ accountId, mediaEnabled }),
}));
const originalClient = window.axios;
let wrapper;
beforeEach(() => {
  window.axios = axios;
  accountId.value = 31;
  mediaEnabled.value = true;
  route.params.companyId = '3';
  route.query = {};
});
afterEach(() => {
  wrapper?.unmount();
  window.axios = originalClient;
});
const mountView = () =>
  mount(CompanyMediaView, {
    global: {
      stubs: {
        CompanyMedia: true,
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
      },
    },
  });

it('loads the real company name and preserves filters when returning to its media tab', async () => {
  route.query = {
    media: JSON.stringify({ q: 'report', page: 2 }),
    retained: 'yes',
  };
  axios.get.mockResolvedValue({
    data: { payload: { id: 3, name: 'Empresa autorizada' } },
  });
  wrapper = mountView();
  expect(wrapper.find('[role="status"]').exists()).toBe(true);
  await flushPromises();
  expect(axios.get).toHaveBeenCalledWith('/api/v1/accounts/31/companies/3');
  expect(wrapper.find('h1').text()).toBe('Empresa autorizada');
  expect(
    wrapper.findAllComponents({ name: 'RouterLink' })[1].props('to')
  ).toEqual({
    name: 'companies_dashboard_show',
    params: { accountId: 31, companyId: 3 },
    query: route.query,
  });
});

it('returns to the media tab even when the expanded page was opened directly', async () => {
  axios.get.mockResolvedValue({
    data: { payload: { id: 3, name: 'Empresa' } },
  });
  wrapper = mountView();
  await flushPromises();
  expect(
    wrapper.findAllComponents({ name: 'RouterLink' })[1].props('to').query.media
  ).toBe('{}');
});

it.each(['account', 'company'])(
  'clears the prior company immediately and ignores stale responses after changing %s',
  async dimension => {
    let first;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          first = resolve;
        })
    );
    axios.get.mockResolvedValue({
      data: { payload: { id: 9, name: 'Empresa atual' } },
    });
    wrapper = mountView();
    if (dimension === 'account') accountId.value = 42;
    else route.params.companyId = '9';
    await flushPromises();
    first({ data: { payload: { id: 3, name: 'Empresa anterior' } } });
    await flushPromises();
    expect(wrapper.find('h1').text()).toBe('Empresa atual');
    expect(wrapper.text()).not.toContain('Empresa anterior');
    let next;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          next = resolve;
        })
    );
    accountId.value = 50;
    await flushPromises();
    expect(wrapper.text()).not.toContain('Empresa atual');
    next({ data: { payload: { id: 9, name: 'Conta seguinte' } } });
    await flushPromises();
    expect(wrapper.find('h1').text()).toBe('Conta seguinte');
  }
);

it('shows a company-specific error and retries the authorized company endpoint', async () => {
  axios.get.mockRejectedValueOnce(new Error('offline'));
  wrapper = mountView();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').text()).toContain(
    'RELATIONSHIPS.MEDIA.COMPANY_ERROR'
  );
  axios.get.mockResolvedValueOnce({
    data: { payload: { id: 3, name: 'Nome recuperado' } },
  });
  await wrapper.find('button').trigger('click');
  await flushPromises();
  expect(wrapper.find('h1').text()).toBe('Nome recuperado');
});

it('does not request or render company data when the media feature is disabled', async () => {
  mediaEnabled.value = false;
  wrapper = mountView();
  await flushPromises();
  expect(axios.get).not.toHaveBeenCalled();
  expect(wrapper.find('main').exists()).toBe(false);
});

it('invalidates a pending company response on unmount', async () => {
  let resolve;
  axios.get.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  wrapper = mountView();
  wrapper.unmount();
  resolve({ data: { payload: { id: 3, name: 'Late company' } } });
  await flushPromises();
  expect(wrapper.find('h1').exists()).toBe(false);
});
