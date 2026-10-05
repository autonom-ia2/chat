import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/contactImportJourney.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/contactImportJourney.json';
import ContactImportPage from '../ContactImportPage.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const api = vi.hoisted(() => ({
  upload: vi.fn(),
  show: vi.fn(),
  chooseColumns: vi.fn(),
  setCompanies: vi.fn(),
  confirm: vi.fn(),
  downloadProblems: vi.fn(),
}));
vi.mock('dashboard/api/contactImports', () => ({ default: api }));

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
  Element.prototype.scrollIntoView = vi.fn();
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});
afterEach(() => vi.clearAllMocks());

const columns = [
  {
    index: 0,
    header: 'Segurado',
    non_blank_count: 100,
    valid_phone_count: 0,
    valid_email_count: 0,
  },
  {
    index: 1,
    header: 'Fone 1',
    non_blank_count: 100,
    valid_phone_count: 98,
    valid_email_count: 0,
  },
  {
    index: 2,
    header: 'Corretora',
    non_blank_count: 96,
    valid_phone_count: 0,
    valid_email_count: 0,
  },
  {
    index: 3,
    header: 'Email comercial',
    non_blank_count: 40,
    valid_phone_count: 0,
    valid_email_count: 40,
  },
  {
    index: 4,
    header: 'Vencimento',
    non_blank_count: 90,
    valid_phone_count: 0,
    valid_email_count: 0,
  },
];

const needsChoice = {
  id: 7,
  status: 'needs_column_choice',
  flow: 'contacts',
  source_filename: 'clientes.xlsx',
  total_rows: 103,
  create_companies: true,
  schema_resolution: {
    method: 'deterministic',
    columns,
    targets: {
      name: { column: 0 },
      phone: { column: 1 },
      email: { column: null },
      company: { column: 2 },
    },
  },
  validation_summary: { errors: {} },
};

const ready = {
  ...needsChoice,
  status: 'ready_to_confirm',
  valid_rows: 98,
  invalid_rows: 5,
  schema_resolution: {
    ...needsChoice.schema_resolution,
    method: 'manual',
    manual_mapping: { name: 0, phone: 1, email: 3, company: 2 },
  },
  validation_summary: {
    errors: { invalid_brazilian_mobile_number: 5 },
    existing_contacts: 41,
    contact_attributes: [
      {
        column: 'Vencimento',
        key: 'vencimento',
        label: 'Vencimento',
        existing: false,
      },
    ],
    companies: {
      available: true,
      companies_created: 15,
      companies_reused: 8,
      contacts_linked: 92,
      contacts_kept: 4,
    },
  },
  problem_rows: [
    {
      row_number: 14,
      phone: '+55 41 3XXX-XX21',
      email: null,
      errors: ['invalid_brazilian_mobile_number'],
    },
  ],
};

const mountPage = () =>
  mount(ContactImportPage, {
    attachTo: document.body,
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Spinner: true },
    },
  });

const uploadWith = async (wrapper, payload) => {
  api.upload.mockResolvedValue({ data: { payload } });
  const input = wrapper.get('[data-test="file-input"]');
  Object.defineProperty(input.element, 'files', {
    value: [new File(['a'], 'clientes.xlsx')],
  });
  await input.trigger('change');
  await flushPromises();
};

const pick = async (wrapper, target, label) => {
  const row = wrapper.get(`[data-target="${target}"]`);
  await row.get('[role="combobox"]').trigger('click');
  const option = row
    .findAll('[role="option"]')
    .find(item => item.text() === label);
  await option.trigger('click');
};

describe('ContactImportPage (#1006)', () => {
  it('asks for the columns, lets the person change them and sends the choice', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, needsChoice);

    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.find('[data-test="choose-columns"]').exists()).toBe(true);
    expect(
      wrapper.get('[data-test="import"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[data-target="phone"]').text()).toContain('98 valid');

    await pick(wrapper, 'email', 'Email comercial');
    api.chooseColumns.mockResolvedValue({
      data: { payload: { ...needsChoice, status: 'validating' } },
    });
    await wrapper.get('[data-test="apply-columns"]').trigger('click');
    await flushPromises();

    expect(api.chooseColumns).toHaveBeenCalledWith(7, {
      name: 0,
      phone: 1,
      email: 3,
      company: 2,
    });
    expect(wrapper.find('[data-test="reading"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('does not send a choice without mobile nor e-mail ("Não tem")', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, needsChoice);

    await pick(wrapper, 'phone', 'There is none');

    expect(
      wrapper.get('[data-test="apply-columns"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain('Choose the mobile or the e-mail column.');
    wrapper.unmount();
  });

  it('shows counts, problem rows, new attributes and companies, then imports', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, ready);

    expect(wrapper.get('[data-test="people-ready"]').text()).toContain('98');
    expect(wrapper.get('[data-test="people-split"]').text()).toBe(
      '41 already were your contacts · 57 new'
    );
    expect(wrapper.get('[data-attribute="vencimento"]').text()).toContain(
      'new attribute'
    );
    expect(wrapper.get('[data-company-tile="NEW"]').text()).toContain('15');
    expect(wrapper.get('[data-company-tile="KEPT"]').text()).toContain('4');

    await wrapper.get('[data-test="problems-toggle"]').trigger('click');
    const problems = wrapper.get('[data-test="problems"]').text();
    expect(problems).toContain('+55 41 3XXX-XX21');
    expect(problems).toContain('Not a Brazilian mobile number');

    api.confirm.mockResolvedValue({
      data: { payload: { ...ready, status: 'queued' } },
    });
    await wrapper.get('[data-test="import"]').trigger('click');
    await flushPromises();

    expect(api.confirm).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-test="importing"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('turns "Create and link" off with a real switch and saves it', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, ready);
    api.setCompanies.mockResolvedValue({
      data: { payload: { ...ready, create_companies: false } },
    });

    const toggle = wrapper.get('[data-test="companies-switch"]');
    expect(toggle.attributes('role')).toBe('switch');
    expect(toggle.attributes('aria-checked')).toBe('true');
    await toggle.trigger('click');
    await flushPromises();

    expect(api.setCompanies).toHaveBeenCalledWith(7, false);
    expect(toggle.attributes('aria-checked')).toBe('false');
    expect(wrapper.find('[data-test="companies-off"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('hides the companies block when the account has no companies (C6)', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, {
      ...ready,
      validation_summary: {
        ...ready.validation_summary,
        companies: { available: false },
      },
    });

    expect(wrapper.find('[data-test="companies-switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-target="company"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('shows the result after importing', async () => {
    const wrapper = mountPage();
    await uploadWith(wrapper, {
      ...ready,
      status: 'completed',
      imported_contacts_count: 98,
      existing_contacts_count: 41,
      failed_contacts_count: 0,
      companies: { created: 15 },
      validation_summary: {
        ...ready.validation_summary,
        contact_attributes_created: 1,
      },
    });

    expect(wrapper.get('[data-result="CREATED"]').text()).toContain('57');
    expect(wrapper.get('[data-result="ATTRIBUTES"]').text()).toContain('1');
    wrapper.unmount();
  });
});

// B1a: the screen never names the engine that reads the columns.
describe('contactImportJourney catalogs', () => {
  const texts = catalog => JSON.stringify(catalog);

  it.each([
    ['en', en],
    ['pt_BR', ptBR],
  ])('%s has no "Jev", "IA" or "AI"', (_locale, catalog) => {
    const words = texts(catalog).split(/[^A-Za-zÀ-ú]+/);
    expect(words).not.toContain('Jev');
    expect(words).not.toContain('IA');
    expect(words).not.toContain('AI');
  });

  it('pt_BR has every key of en', () => {
    const keys = (object, prefix = '') =>
      Object.entries(object).flatMap(([key, value]) =>
        typeof value === 'object'
          ? keys(value, `${prefix}${key}.`)
          : [`${prefix}${key}`]
      );
    expect(keys(ptBR).sort()).toEqual(keys(en).sort());
  });
});
