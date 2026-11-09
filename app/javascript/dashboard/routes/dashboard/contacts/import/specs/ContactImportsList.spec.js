import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/contactImportJourney.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/contactImportJourney.json';
import ContactImportsList from '../ContactImportsList.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const api = vi.hoisted(() => ({ list: vi.fn() }));
vi.mock('dashboard/api/contactImports', () => ({ default: api }));

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});
afterEach(() => vi.clearAllMocks());

const fromAutomation = {
  id: 9,
  status: 'completed_with_failures',
  origin: 'automation',
  name: 'Lista do RH',
  source_filename: null,
  total_rows: 4,
  imported_contacts_count: 3,
  failed_count: 1,
  created_at: '2026-11-09T13:00:00Z',
  created_by: { id: 1, name: 'Luciana' },
};

const fromFile = {
  id: 7,
  status: 'completed',
  origin: 'file',
  name: null,
  source_filename: 'clientes.xlsx',
  total_rows: 100,
  imported_contacts_count: 98,
  failed_count: 2,
  created_at: '2026-11-08T13:00:00Z',
  created_by: { id: 2, name: 'Rodrigo' },
};

const page = (payload, { count = payload.length, current = 1 } = {}) => ({
  data: { payload, meta: { count, current_page: current, per_page: 25 } },
});

const mountList = (locale = 'en') =>
  mount(ContactImportsList, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }),
      ],
      stubs: { Spinner: true },
    },
  });

describe('ContactImportsList (#2771)', () => {
  it('lists file and automation imports with origin, who and the counts', async () => {
    api.list.mockResolvedValue(page([fromAutomation, fromFile]));

    const wrapper = mountList();
    await flushPromises();

    expect(api.list).toHaveBeenCalledWith(1);
    const [automation, file] = wrapper.findAll('[data-import]');
    expect(automation.text()).toContain('Lista do RH');
    expect(automation.get('[data-test="origin"]').text()).toBe('Automation');
    expect(automation.get('[data-test="who"]').text()).toContain('by Luciana');
    expect(automation.get('[data-test="counts"]').text()).toBe(
      '3 came in · 1 left out'
    );
    expect(automation.get('[data-test="status"]').text()).toBe(
      'Done, some left out'
    );
    expect(file.text()).toContain('clientes.xlsx');
    expect(file.get('[data-test="origin"]').text()).toBe('Spreadsheet');
    expect(file.get('[data-test="status"]').text()).toBe('Done');
    expect(wrapper.find('[data-test="more"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('opens the result of the import clicked', async () => {
    api.list.mockResolvedValue(page([fromAutomation]));
    const wrapper = mountList();
    await flushPromises();

    await wrapper.get('[data-import="9"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'contacts_import_journey',
      params: { importId: 9 },
    });
    wrapper.unmount();
  });

  it('shows more on request, adding the next page', async () => {
    api.list
      .mockResolvedValueOnce(page([fromAutomation], { count: 2 }))
      .mockResolvedValueOnce(page([fromFile], { count: 2, current: 2 }));
    const wrapper = mountList();
    await flushPromises();

    await wrapper.get('[data-test="more"]').trigger('click');
    await flushPromises();

    expect(api.list).toHaveBeenLastCalledWith(2);
    expect(wrapper.findAll('[data-import]')).toHaveLength(2);
    expect(wrapper.find('[data-test="more"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('a draft still being checked says it waits for the person', async () => {
    api.list.mockResolvedValue(
      page([{ ...fromFile, status: 'ready_to_confirm' }])
    );
    const wrapper = mountList();
    await flushPromises();

    expect(wrapper.get('[data-test="status"]').text()).toBe(
      'Waiting for you to check'
    );
    wrapper.unmount();
  });

  it('says when there is no import yet, in pt_BR', async () => {
    api.list.mockResolvedValue(page([]));
    const wrapper = mountList('pt_BR');
    await flushPromises();

    expect(wrapper.get('[data-test="empty"]').text()).toBe(
      'Nenhuma lista de contatos entrou ainda.'
    );
    wrapper.unmount();
  });

  it('says when the list could not load', async () => {
    api.list.mockRejectedValue(new Error('boom'));
    const wrapper = mountList();
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toBe(
      'Could not load the imports. Try again.'
    );
    expect(wrapper.find('[data-test="empty"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
