import { mount, flushPromises } from '@vue/test-utils';
import { ref, reactive } from 'vue';
import axios from 'axios';
import CompanyMedia from '../CompanyMedia.vue';

const accountId = ref(31);
const route = reactive({ query: {} });
const context = vi.hoisted(() => ({ push: vi.fn(), replace: vi.fn() }));
vi.mock('axios', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
    locale: ref('en'),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => context,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId }),
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
        teleport: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  Element.prototype.scrollIntoView = vi.fn();
  accountId.value = 31;
  route.query = {};
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
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/companies/3/media',
    { params: { q: 'arquivo-antigo', group: 'contact', page: 1, per_page: 25 } }
  );
  await wrapper
    .find('button[aria-label="RELATIONSHIPS.MEDIA.ACTIONS"]')
    .trigger('click');
  await flushPromises();
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

it.each(['unmount', 'company', 'account'])(
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
      .find('button[aria-label="RELATIONSHIPS.MEDIA.ACTIONS"]')
      .trigger('click');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIPS.MEDIA.DOWNLOAD')
      .trigger('click');
    if (action === 'unmount') wrapper.unmount();
    else if (action === 'account') accountId.value = 42;
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

it('restores filters, shows separate groups for distinct contact IDs with the same name, and paginates on the server', async () => {
  route.query = {
    retained: 'yes',
    media: JSON.stringify({
      q: 'report',
      group: 'contact',
      type: 'file',
      contact_id: '4',
      from: '2026-09-01',
      to: '2026-09-29',
      page: 2,
    }),
  };
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [] }
        : response(
            [
              row(1, 'same.pdf'),
              row(2, 'same.pdf'),
              {
                ...row(3, 'same.pdf'),
                contact: { id: 5, name: 'Contato sintético' },
              },
            ],
            76
          )
    )
  );
  const wrapper = mountMedia();
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/companies/3/media',
    {
      params: {
        q: 'report',
        group: 'contact',
        type: 'file',
        contact_id: '4',
        from: '2026-09-01',
        to: '2026-09-29',
        page: 2,
        per_page: 25,
      },
    }
  );
  expect(wrapper.findAll('[data-media-group]')).toHaveLength(2);
  expect(wrapper.findAll('[data-media-row]')).toHaveLength(3);
  expect(wrapper.text()).toContain('"page":2,"pages":4');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.NEXT')
    .trigger('click');
  await flushPromises();
  expect(axios.get.mock.lastCall[1].params.page).toBe(3);
  expect(context.replace.mock.lastCall[0].query.retained).toBe('yes');
  wrapper.unmount();
});

it('clears every filter and resets pagination while preserving unrelated query parameters', async () => {
  route.query = {
    keep: '1',
    media: JSON.stringify({
      q: 'report',
      type: 'file',
      contact_id: '4',
      from: '2026-09-01',
      to: '2026-09-29',
      group: 'contact',
      page: 3,
    }),
  };
  axios.get.mockImplementation(url =>
    Promise.resolve(url.endsWith('/contacts') ? { data: [] } : response([], 0))
  );
  const wrapper = mountMedia();
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.NO_RESULTS');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.MEDIA.CLEAR')
    .trigger('click');
  await flushPromises();
  expect(axios.get.mock.lastCall[1]).toEqual({
    params: { page: 1, per_page: 25 },
  });
  expect(JSON.parse(context.replace.mock.lastCall[0].query.media)).toEqual({
    q: '',
    type: '',
    contact_id: '',
    from: '',
    to: '',
    group: '',
    page: 1,
  });
  expect(context.replace.mock.lastCall[0].query.keep).toBe('1');
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.EMPTY');
  expect(wrapper.text()).not.toContain('RELATIONSHIPS.MEDIA.NO_RESULTS');
  wrapper.unmount();
});

it('keeps correct media visible when contact search fails and offers a contact-specific retry', async () => {
  axios.get.mockImplementation(url =>
    url.endsWith('/contacts')
      ? Promise.reject(new Error('contacts failed'))
      : Promise.resolve(response([row(1, 'visible.pdf')]))
  );
  const wrapper = mountMedia();
  await flushPromises();
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper
    .find('button[aria-label="RELATIONSHIPS.CONTACTS"]')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('visible.pdf');
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.CONTACT_ERROR');
  expect(wrapper.text()).not.toContain('RELATIONSHIPS.MEDIA.LOAD_ERROR');
  axios.get.mockResolvedValue({
    data: [{ id: 12, name: 'Contato recuperado' }],
  });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.RETRY')
    .trigger('click');
  await flushPromises();
  expect(axios.get.mock.lastCall[0]).toContain('/media/contacts');
  expect(wrapper.text()).toContain('Contato recuperado');
  expect(wrapper.text()).toContain('visible.pdf');
  wrapper.unmount();
});

it('searches contacts on the server without submitting the form and ignores late search results after clearing', async () => {
  let resolveSearch;
  axios.get.mockImplementation((url, config) => {
    if (!url.endsWith('/contacts'))
      return Promise.resolve(response([row(1, 'visible.pdf')]));
    if (config.params.q === 'late')
      return new Promise(resolve => {
        resolveSearch = resolve;
      });
    return Promise.resolve({ data: [{ id: 4, name: 'Contato sintético' }] });
  });
  const wrapper = mountMedia();
  await flushPromises();
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper
    .find('button[aria-label="RELATIONSHIPS.CONTACTS"]')
    .trigger('click');
  await flushPromises();
  const search = wrapper.findAll('input[type="search"]')[1];
  await search.setValue('late');
  await search.trigger('keydown', { key: 'Enter' });
  expect(context.replace).not.toHaveBeenCalled();
  await wrapper.find('input[type="search"]').setValue('filename');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.MEDIA.CLEAR')
    .trigger('click');
  resolveSearch({ data: [{ id: 8, name: 'Late contact' }] });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Late contact');
  expect(
    wrapper
      .findAll('button')
      .filter(button => button.attributes('type') === undefined)
  ).toHaveLength(0);
  wrapper.unmount();
});

it('isolates media and contact responses when switching accounts', async () => {
  const pending = [];
  axios.get.mockImplementation(url => {
    if (url.includes('/accounts/31/'))
      return new Promise(resolve => {
        pending.push({ url, resolve });
      });
    return Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [{ id: 6, name: 'New contact' }] }
        : response([row(2, 'new-account.pdf')])
    );
  });
  const wrapper = mountMedia();
  accountId.value = 42;
  await flushPromises();
  pending.forEach(({ url, resolve }) =>
    resolve(
      url.endsWith('/contacts')
        ? { data: [{ id: 4, name: 'Old contact' }] }
        : response([row(1, 'old-account.pdf')])
    )
  );
  await flushPromises();
  expect(wrapper.text()).toContain('new-account.pdf');
  expect(wrapper.text()).not.toContain('old-account.pdf');
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper
    .find('button[aria-label="RELATIONSHIPS.CONTACTS"]')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Old contact');
  expect(wrapper.text()).toContain('New contact');
  wrapper.unmount();
});

it('retries a listing failure and shows friendly types, sizes, real author and authorized preview', async () => {
  axios.get.mockImplementation(url =>
    url.endsWith('/contacts')
      ? Promise.resolve({ data: [] })
      : Promise.reject(new Error('offline'))
  );
  const wrapper = mountMedia();
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.LOAD_ERROR');
  axios.get.mockResolvedValue(response([row(1, 'original.pdf')]));
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.RETRY')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.PDF');
  expect(wrapper.text()).toContain('1 KB');
  expect(wrapper.text()).not.toContain('application/pdf');
  expect(wrapper.text()).toContain('Agente sintético');
  const click = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  axios.get.mockResolvedValue({
    data: { url: 'https://example.test/original' },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.MEDIA.PREVIEW')
    .trigger('click');
  await flushPromises();
  expect(axios.get).toHaveBeenLastCalledWith(
    '/api/v1/accounts/31/companies/3/media/1',
    { params: { inline: true } }
  );
  expect(click).toHaveBeenCalledOnce();
  click.mockRestore();
  wrapper.unmount();
});

it('uses the compact server page and places view all in the header with applied filters', async () => {
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [] }
        : response([row(1, 'original.pdf')], 10)
    )
  );
  const wrapper = mountMedia();
  await wrapper.setProps({ expanded: false });
  await wrapper.find('input[type="search"]').setValue('original');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.get.mock.lastCall[1]).toEqual({
    params: { q: 'original', page: 1, per_page: 5 },
  });
  expect(wrapper.find('table').exists()).toBe(false);
  await wrapper.find('header button').trigger('click');
  expect(context.push.mock.lastCall[0]).toMatchObject({
    name: 'relationships_company_media',
    params: { accountId: 31, companyId: 3 },
  });
  expect(JSON.parse(context.push.mock.lastCall[0].query.media).q).toBe(
    'original'
  );
  wrapper.unmount();
});

it('applies the selected contact ID, type and dates without a dropdown submitting the form', async () => {
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts')
        ? { data: [{ id: 44, name: 'Nome real selecionado' }] }
        : response([row(1, 'file.pdf')])
    )
  );
  const wrapper = mountMedia();
  await flushPromises();
  await wrapper.find('button[aria-controls]').trigger('click');
  await wrapper.find('[role="combobox"]').trigger('click');
  await wrapper.find('[role="option"][data-value="image"]').trigger('click');
  await wrapper
    .find('button[aria-label="RELATIONSHIPS.CONTACTS"]')
    .trigger('click');
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Nome real selecionado')
    .trigger('click');
  expect(context.replace).not.toHaveBeenCalled();
  expect(
    wrapper.find('button[aria-label="RELATIONSHIPS.CONTACTS"]').text()
  ).toBe('Nome real selecionado');
  const dates = wrapper.findAll('input[type="date"]');
  await dates[0].setValue('2026-09-01');
  await dates[1].setValue('2026-09-29');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.get.mock.lastCall[1]).toEqual({
    params: {
      contact_id: '44',
      type: 'image',
      from: '2026-09-01',
      to: '2026-09-29',
      page: 1,
      per_page: 25,
    },
  });
  wrapper.unmount();
});

it('keeps listing data after a file action failure and retries the same authorized original', async () => {
  axios.get.mockImplementation(url =>
    Promise.resolve(
      url.endsWith('/contacts') ? { data: [] } : response([row(1, 'file.pdf')])
    )
  );
  const wrapper = mountMedia();
  await flushPromises();
  axios.get.mockRejectedValueOnce(new Error('temporary'));
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.MEDIA.PREVIEW')
    .trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.ACTION_ERROR');
  expect(wrapper.text()).toContain('file.pdf');
  expect(wrapper.text()).not.toContain('RELATIONSHIPS.MEDIA.LOAD_ERROR');
  const click = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  axios.get.mockResolvedValueOnce({
    data: { url: 'https://example.test/original' },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.RETRY')
    .trigger('click');
  await flushPromises();
  expect(axios.get.mock.lastCall).toEqual([
    '/api/v1/accounts/31/companies/3/media/1',
    { params: { inline: true } },
  ]);
  expect(click).toHaveBeenCalledOnce();
  click.mockRestore();
  wrapper.unmount();
});

it.each(['before', 'after'])(
  'clears a file action failure that arrives %s changing the media page',
  async timing => {
    let rejectOriginal;
    axios.get.mockImplementation((url, config) => {
      if (url.endsWith('/contacts')) return Promise.resolve({ data: [] });
      if (url.endsWith('/1'))
        return new Promise((resolve, reject) => {
          rejectOriginal = reject;
        });
      return Promise.resolve(
        response(
          config.params.page === 1
            ? [row(1, 'previous-page.pdf')]
            : [row(2, 'current-page.pdf')],
          26
        )
      );
    });
    const wrapper = mountMedia();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIPS.MEDIA.PREVIEW')
      .trigger('click');
    if (timing === 'before') {
      rejectOriginal(new Error('temporary'));
      await flushPromises();
      expect(wrapper.text()).toContain('RELATIONSHIPS.MEDIA.ACTION_ERROR');
    }
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIPS.NEXT')
      .trigger('click');
    if (timing === 'after') rejectOriginal(new Error('temporary'));
    await flushPromises();
    expect(wrapper.text()).toContain('current-page.pdf');
    expect(wrapper.text()).not.toContain('previous-page.pdf');
    expect(wrapper.text()).not.toContain('RELATIONSHIPS.MEDIA.ACTION_ERROR');
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text() === 'RELATIONSHIPS.RETRY')
    ).toBe(false);
    wrapper.unmount();
  }
);
