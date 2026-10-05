import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { saveDraft } from 'dashboard/components-next/CampaignJourney/campaignDraft';

const api = vi.hoisted(() => ({
  createAudience: vi.fn(),
  show: vi.fn(),
  chooseColumns: vi.fn(),
  setChannels: vi.fn(),
  setCreateCompanies: vi.fn(),
  problemRows: vi.fn(),
  confirm: vi.fn(),
  downloadErrors: vi.fn(),
}));
vi.mock('dashboard/api/campaignJourney', () => ({ audiencesAPI: api }));

const route = vi.hoisted(() => ({ value: null }));
const smsInboxes = vi.hoisted(() => ({ value: [] }));
const push = vi.fn();
const replace = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => route.value,
  useRouter: () => ({ push, replace }),
}));
const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const { default: NewAudiencePage } = await import('../NewAudiencePage.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const RESOLUTION = {
  method: 'deterministic',
  targets: {
    name: { column: 0, header: 'Responsável', confident: false },
    phone: { column: 3, header: 'Celular', confident: false },
    email: { column: 1, header: 'Email comercial', confident: false },
    company: { column: null, header: null, confident: false },
  },
  columns: [
    { index: 0, header: 'Responsável', non_blank_count: 100 },
    { index: 1, header: 'Email comercial', valid_email_count: 0 },
    { index: 2, header: 'Corretora', non_blank_count: 100 },
    { index: 3, header: 'Celular', valid_phone_count: 98 },
  ],
};

const base = {
  id: 42,
  name: 'Auto outubro',
  flow: 'audience',
  schema_resolution: RESOLUTION,
  extra_columns: [],
  downloads: { error_csv: true },
};
const choosing = { ...base, status: 'needs_column_choice' };
const ready = {
  ...base,
  status: 'ready_to_confirm',
  valid_rows: 98,
  invalid_rows: 2,
  extra_columns: ['Vencimento'],
  schema_resolution: {
    ...RESOLUTION,
    manual_mapping: { name: 0, phone: 3, email: null, company: 2 },
  },
  channels: {
    email: { enabled: false, count: 0 },
    whatsapp: { enabled: true, count: 98 },
  },
  create_companies: true,
  validation_summary: {
    errors: { invalid_brazilian_mobile_number: 1, missing_contact: 1 },
    companies: {
      available: true,
      companies_created: 15,
      companies_reused: 8,
      contacts_linked: 92,
      contacts_kept: 4,
    },
  },
};
const ok = payload => Promise.resolve({ data: { payload } });

const mountPage = (query = {}) => {
  route.value = reactive({ query });
  const module = getters => ({ namespaced: true, getters });
  const store = createStore({
    getters: { getCurrentAccountId: () => 1 },
    modules: {
      inboxes: module({ getInboxes: () => smsInboxes.value }),
      emailSenderIdentities: module({ getIdentities: () => [] }),
      globalConfig: module({ get: () => ({}) }),
      accounts: module({ isFeatureEnabledonAccount: () => () => true }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enJourney },
  });
  return mount(NewAudiencePage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
};

beforeEach(() => {
  vi.useFakeTimers();
  Object.values(api).forEach(fn => fn.mockReset());
  push.mockClear();
  replace.mockClear();
  alert.mockClear();
  window.localStorage.clear();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('Novo público (PRD §6.6)', () => {
  it('J2: opened from a campaign, says which campaign is waiting', async () => {
    saveDraft(1, { title: 'Renovação auto — outubro' });
    const wrapper = mountPage({ from: 'campaign' });
    await flushPromises();

    expect(wrapper.find('[data-test="from-campaign"]').text()).toBe(
      'You are creating an audience for the campaign "Renovação auto — outubro". When you save it, we take you back to it.'
    );
    wrapper.unmount();
  });

  it('B2: uploads, waits for the reading and sends the chosen column indices', async () => {
    api.createAudience.mockReturnValue(ok({ ...base, status: 'validating' }));
    api.show.mockReturnValue(ok(choosing));
    api.chooseColumns.mockReturnValue(ok({ ...base, status: 'validating' }));
    const wrapper = mountPage();
    await flushPromises();

    await wrapper
      .find('[data-test="audience-upload"] input[type="text"]')
      .setValue('Auto outubro');
    const file = new File(['Responsável;Email comercial'], 'base.csv');
    const input = wrapper.find('[data-test="audience-file"]');
    Object.defineProperty(input.element, 'files', { value: [file] });
    await input.trigger('change');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(api.createAudience).toHaveBeenCalledWith({
      name: 'Auto outubro',
      file,
    });
    expect(wrapper.find('[data-test="audience-working"]').exists()).toBe(true);
    expect(replace).toHaveBeenCalledWith({ query: { import: '42' } });

    await vi.advanceTimersByTimeAsync(1600);
    await flushPromises();
    expect(api.show).toHaveBeenCalledWith(42);
    const choices = wrapper.findAllComponents(ChoiceSelect);
    expect(choices).toHaveLength(4);
    expect(wrapper.text()).toContain('Which column has each piece of data?');

    // Corretora is the company; the e-mail column has no valid e-mail.
    choices[3].vm.$emit('update:modelValue', '2');
    choices[2].vm.$emit('update:modelValue', 'none');
    await flushPromises();
    await wrapper.find('[data-test="apply-columns"]').trigger('click');
    await flushPromises();

    expect(api.chooseColumns).toHaveBeenCalledWith(42, {
      name: 0,
      phone: 3,
      email: null,
      company: 2,
    });
    wrapper.unmount();
  });

  it('B5, J5, J6, C4: review shows counts, channels and companies', async () => {
    api.show.mockReturnValue(ok(ready));
    api.problemRows.mockRejectedValue({ response: { status: 404 } });
    api.setChannels.mockReturnValue(
      ok({
        ...ready,
        channels: {
          ...ready.channels,
          whatsapp: { enabled: false, count: 98 },
        },
      })
    );
    api.setCreateCompanies.mockReturnValue(
      ok({ ...ready, create_companies: false })
    );
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    expect(wrapper.find('[data-test="people-summary"]').text()).toBe(
      '98 ready · 2 with a problem'
    );
    expect(wrapper.find('[data-test="other-columns"]').text()).toContain(
      'Vencimento'
    );

    const email = wrapper.find('[data-channel="email"]');
    expect(email.text()).toBe('Email · no data');
    expect(email.attributes('aria-checked')).toBe('false');
    expect(email.attributes('disabled')).toBeDefined();
    const whatsapp = wrapper.find('[data-channel="whatsapp"]');
    expect(whatsapp.text()).toBe('WhatsApp · 98');
    expect(whatsapp.attributes('aria-checked')).toBe('true');
    await whatsapp.trigger('click');
    await flushPromises();
    expect(api.setChannels).toHaveBeenCalledWith(42, { whatsapp: false });
    expect(
      wrapper.find('[data-channel="whatsapp"]').attributes('aria-checked')
    ).toBe('false');

    await wrapper.find('[data-test="toggle-problems"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-test="reason-tally"]').text()).toContain(
      'Not a valid mobile number: 1'
    );
    expect(wrapper.find('[data-test="download-problems"]').exists()).toBe(true);

    const companies = wrapper.find('[data-test="audience-companies"]');
    expect(companies.text()).toContain('The Corretora column');
    expect(companies.text()).toContain('15');
    expect(companies.text()).toContain('already had another company — kept');
    const toggle = wrapper.find('[data-test="companies-switch"]');
    expect(toggle.attributes('role')).toBe('switch');
    await toggle.trigger('click');
    await flushPromises();
    expect(api.setCreateCompanies).toHaveBeenCalledWith(42, false);
    wrapper.unmount();
  });

  it('B8: shows who stays in the audience but does not receive', async () => {
    api.show.mockReturnValue(
      ok({
        ...ready,
        reachability: {
          whatsapp: { total: 98, receive: 95, opted_out: 3 },
          email: {
            total: 0,
            receive: 0,
            unsubscribed: 0,
            bounced: 0,
            suppressed: 0,
          },
        },
      })
    );
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    const tile = wrapper.find('[data-test="not-receiving"]');
    expect(tile.text()).toContain('3');
    expect(tile.text()).toContain('do not receive');
    expect(tile.text()).toContain('WhatsApp: refused messages · 3');
    wrapper.unmount();
  });

  it('B5: lists masked reasons per row when the backend sends them', async () => {
    api.show.mockReturnValue(ok(ready));
    api.problemRows.mockReturnValue(
      Promise.resolve({
        data: {
          payload: [
            {
              row_number: 14,
              contact_masked: '+55 41 3XXX-XX21',
              errors: ['invalid_brazilian_mobile_number'],
            },
          ],
        },
      })
    );
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    await wrapper.find('[data-test="toggle-problems"]').trigger('click');
    await flushPromises();

    const row = wrapper.find('[data-problem-row="14"]');
    expect(row.findAll('td')).toHaveLength(3);
    expect(row.text()).toContain('+55 41 3XXX-XX21');
    expect(row.text()).toContain('Not a valid mobile number');
    wrapper.unmount();
  });

  it('channel in use by a campaign: says which one', async () => {
    api.show.mockReturnValue(ok(ready));
    api.setChannels.mockRejectedValue({
      response: {
        data: { code: 'audience_in_use', campaigns: [{ title: 'Renovação' }] },
      },
    });
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    await wrapper.find('[data-channel="whatsapp"]').trigger('click');
    await flushPromises();

    expect(alert).toHaveBeenCalledWith(expect.stringContaining('Renovação'));
    wrapper.unmount();
  });

  it('J3: saving from a campaign goes back to it with the audience selected', async () => {
    api.show.mockReturnValueOnce(ok(ready)).mockReturnValue(
      ok({
        ...ready,
        status: 'completed',
        imported_contacts_count: 98,
        existing_contacts_count: 41,
      })
    );
    api.confirm.mockReturnValue(ok({ ...ready, status: 'importing' }));
    const wrapper = mountPage({ import: '42', from: 'campaign' });
    await flushPromises();

    await wrapper.find('[data-test="save-audience"]').trigger('click');
    await flushPromises();
    expect(api.confirm).toHaveBeenCalledWith(42);
    expect(wrapper.find('[data-test="audience-working"]').text()).toContain(
      'Saving the audience'
    );

    await vi.advanceTimersByTimeAsync(1600);
    await flushPromises();
    const done = wrapper.find('[data-test="audience-done"]').text();
    expect(done).toContain('Audience saved');
    expect(done).toContain('new contacts57');
    expect(done).toContain('were already your contacts41');
    await wrapper.find('[data-test="back-to-campaign"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_new',
      query: { audience: '42', returned: '1' },
    });
    wrapper.unmount();
  });

  it('B9: leaving before saving never confirms the import', async () => {
    api.show.mockReturnValue(ok(ready));
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    await wrapper.find('[data-test="cancel-audience"]').trigger('click');

    expect(api.confirm).not.toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith({ name: 'campaigns_journey_audiences' });
    wrapper.unmount();
  });

  it('B6: a file without valid rows is refused with the reasons and cannot be saved', async () => {
    api.show.mockReturnValue(
      ok({
        ...ready,
        status: 'validation_failed',
        valid_rows: 0,
        invalid_rows: 3,
        validation_summary: {
          errors: { no_valid_rows: 1, missing_contact: 3 },
        },
      })
    );
    const wrapper = mountPage({ import: '42' });
    await flushPromises();

    const refused = wrapper.find('[data-test="audience-refused"]');
    expect(refused.text()).toContain('No row can be used');
    expect(refused.text()).toContain('No mobile or email: 3');
    expect(wrapper.find('[data-test="save-audience"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('#1004: SMS badge locked "sem caixa" without an SMS inbox, free with one', async () => {
    api.show.mockReturnValue(ok(ready));
    api.setChannels.mockRejectedValue({
      response: { data: { error: 'campaign_import.channel_without_inbox' } },
    });
    let wrapper = mountPage({ import: '42' });
    await flushPromises();

    const locked = wrapper.find('[data-channel="sms"]');
    expect(locked.text()).toBe('SMS · no inbox');
    expect(locked.attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('The account has no SMS inbox connected.');
    wrapper.unmount();

    smsInboxes.value = [{ id: 3, channel_type: 'Channel::Sms' }];
    wrapper = mountPage({ import: '42' });
    await flushPromises();
    const free = wrapper.find('[data-channel="sms"]');
    expect(free.text()).toBe('SMS · 98');
    expect(free.attributes('aria-checked')).toBe('false');
    await free.trigger('click');
    await flushPromises();
    expect(api.setChannels).toHaveBeenCalledWith(42, { sms: true });
    // The server says there is no SMS inbox: the badge locks as "sem caixa".
    expect(wrapper.find('[data-channel="sms"]').text()).toBe('SMS · no inbox');
    smsInboxes.value = [];
    wrapper.unmount();
  });
});
