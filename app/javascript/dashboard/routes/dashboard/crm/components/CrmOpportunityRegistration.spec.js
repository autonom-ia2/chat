import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import CrmOpportunityRegistration from './CrmOpportunityRegistration.vue';
import {
  newRegistrationDraft,
  registrationPayload,
  companyDomain,
} from './opportunityRegistration';

const session = {
  attributesEnabled: ref(true),
  companiesEnabled: ref(true),
  state: ref({ definitions: [], configuration: null, error: false }),
  load: vi.fn(),
};
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => session,
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { search: vi.fn(), show: vi.fn() },
}));
vi.mock('dashboard/api/companies', () => ({
  default: { search: vi.fn(), show: vi.fn() },
}));
let wrapper;
const make = (draft = {}, props = {}) =>
  mount(CrmOpportunityRegistration, {
    props: { modelValue: { ...newRegistrationDraft(), ...draft }, ...props },
    global: {
      stubs: {
        PhoneNumberInput: {
          template: '<input />',
          methods: { validate: () => true },
        },
        CrmOpportunityCompanyPicker: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  Element.prototype.scrollIntoView = vi.fn();
  session.companiesEnabled.value = true;
  session.attributesEnabled.value = true;
  session.state.value = { definitions: [], configuration: null, error: false };
  ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
  CompanyAPI.search.mockResolvedValue({ data: { payload: [] } });
});
afterEach(() => wrapper?.unmount());

it('requires only a name for a registration without company and performs no writes while typing', () => {
  wrapper = make();
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.draft.name = 'Name only';
  expect(wrapper.vm.canSave).toBe(true);
  expect(ContactAPI.search).not.toHaveBeenCalled();
  expect(CompanyAPI.search).not.toHaveBeenCalled();
  expect(wrapper.findAll('select')).toHaveLength(0);
});
it('requires a selected real company for existing mode and a name for new mode', () => {
  wrapper = make({ name: 'Person' });
  wrapper.vm.setCompanyMode('existing');
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.draft.company = { id: 7 };
  expect(wrapper.vm.canSave).toBe(true);
  wrapper.vm.setCompanyMode('new');
  expect(wrapper.vm.draft.company).toBeNull();
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.draft.companyName = 'New company';
  expect(wrapper.vm.canSave).toBe(true);
});
it('blocks company registration when its capability is removed, but allows explicit no-company', () => {
  wrapper = make({
    name: 'Person',
    companyMode: 'new',
    companyName: 'Company',
  });
  session.companiesEnabled.value = false;
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.setCompanyMode('none');
  expect(wrapper.vm.canSave).toBe(true);
});
it('finds duplicates by exact identity without treating fuzzy names as the same person', async () => {
  wrapper = make({ name: 'Person', email: '  EXISTING@EXAMPLE.COM ' });
  ContactAPI.search.mockResolvedValue({
    data: {
      payload: [
        { id: 7, name: 'Person', email: 'existing@example.com' },
        { id: 8, name: 'Person', email: 'different@example.com' },
      ],
    },
  });
  await wrapper.vm.lookupContact();
  expect(wrapper.vm.contactMatches.map(item => item.id)).toEqual([7]);
});
it('retains both identities when email and phone point to different contacts', async () => {
  wrapper = make({
    name: 'Person',
    email: 'existing@example.com',
    phoneNumber: '+14155552671',
  });
  ContactAPI.search.mockImplementation(term =>
    Promise.resolve({
      data: {
        payload: term.includes('@')
          ? [{ id: 7, name: 'Email', email: term }]
          : [{ id: 8, name: 'Phone', phone_number: term }],
      },
    })
  );
  await wrapper.vm.lookupContact();
  expect(wrapper.vm.contactMatches.map(item => item.id)).toEqual([7, 8]);
  expect(
    wrapper.find('[data-registration-contact-duplicates]').text()
  ).toContain('IDENTITY_CONFLICT');
});
it('ignores an old lookup after the identity changes', async () => {
  let finish;
  wrapper = make({ name: 'Person', email: 'old@example.com' });
  ContactAPI.search.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  const request = wrapper.vm.lookupContact();
  wrapper.vm.draft.email = 'new@example.com';
  finish({ data: { payload: [{ id: 7, email: 'old@example.com' }] } });
  await request;
  expect(wrapper.vm.contactMatches).toEqual([]);
});
it('hydrates canonical contact and company before switching to use existing, never overwrites them', async () => {
  wrapper = make({ name: 'Draft person', companyName: 'Draft company' });
  ContactAPI.show.mockResolvedValue({
    data: { payload: { id: 7, name: 'Existing', company_id: 9 } },
  });
  CompanyAPI.show.mockResolvedValue({
    data: { payload: { id: 9, name: 'Canonical company' } },
  });
  await wrapper.vm.useContact({ id: 7 });
  expect(wrapper.emitted('useContact')[0][0]).toEqual({
    id: 7,
    name: 'Existing',
    company_id: 9,
    company: { id: 9, name: 'Canonical company' },
  });
  expect(wrapper.vm.draft.name).toBe('Draft person');
});
it('keeps a same-name company as a warning, without blocking a different company', async () => {
  wrapper = make({
    name: 'Person',
    companyMode: 'new',
    companyName: 'Equal name',
    companyDomain: 'new.example',
  });
  CompanyAPI.search.mockResolvedValue({
    data: { payload: [{ id: 8, name: 'Equal name', domain: 'other.example' }] },
  });
  await wrapper.vm.lookupCompany();
  expect(wrapper.vm.companyMatches).toHaveLength(1);
  expect(wrapper.vm.companyExact).toBeUndefined();
  expect(wrapper.vm.canSave).toBe(true);
});
it('recognizes a URL domain duplicate and explicitly reuses its ID without company data writes', async () => {
  wrapper = make({
    name: 'Person',
    companyMode: 'new',
    companyName: 'New',
    companyDomain: 'https://EXISTING.example/path',
  });
  const existing = { id: 8, name: 'Existing', domain: 'existing.example' };
  CompanyAPI.search.mockResolvedValue({ data: { payload: [existing] } });
  await wrapper.vm.lookupCompany();
  expect(wrapper.vm.companyExact).toEqual(existing);
  wrapper.vm.useCompany(existing);
  expect(registrationPayload(wrapper.vm.draft).company).toEqual({
    mode: 'existing',
    id: 8,
  });
});
it('shows authoritative field errors and expands company extras without erasing the draft', async () => {
  wrapper = make({
    name: 'Person',
    companyMode: 'new',
    companyName: 'Company',
    companyAttributes: { budget: 'bad' },
  });
  await wrapper.vm.showError({
    section: 'company',
    fields: { 'custom_attributes.budget': 'invalid' },
    matches: [],
  });
  expect(wrapper.vm.companyMore).toBe(true);
  expect(wrapper.vm.companyErrors).toHaveProperty('custom_attributes.budget');
  expect(wrapper.vm.draft.name).toBe('Person');
});
it('shows no private identity for a hidden duplicate response', async () => {
  wrapper = make({ name: 'Person' });
  await wrapper.vm.showError({
    section: 'contact',
    code: 'crm.opportunity.contact_exists',
    fields: {},
    matches: [],
  });
  expect(wrapper.vm.contactMatches).toEqual([]);
  expect(wrapper.find('[data-registration-error]').exists()).toBe(true);
});
it('blocks invalid raw phone even when the previously emitted number was valid', async () => {
  wrapper = make({ name: 'Person', phoneNumber: '+14155552671' });
  wrapper.vm.phone.validate = vi.fn().mockResolvedValue(false);
  expect(await wrapper.vm.validate()).toBe(false);
  expect(wrapper.vm.contactErrors).toHaveProperty('phone_number');
});
it('reveals native invalid fields in a collapsed section without accepting the draft', async () => {
  wrapper = make({ name: 'Person', email: 'invalid' });
  expect(await wrapper.vm.validate()).toBe(false);
  expect(wrapper.vm.contactMore).toBe(true);
});
it('uses the same selected profile attribute definitions and separates contact/company namespaces', () => {
  session.state.value = {
    error: false,
    configuration: {
      surfaces: {
        contact_details: { mode: 'custom', ids: [1, 2] },
        company_details: { mode: 'custom', ids: [3] },
      },
    },
    definitions: [
      {
        id: 1,
        attribute_model: 'contact_attribute',
        attribute_key: 'person',
        attribute_display_type: 'text',
      },
      {
        id: 2,
        attribute_model: 'contact_attribute',
        attribute_key: 'legacy',
        regex_pattern: 'legacy-rule',
      },
      {
        id: 3,
        attribute_model: 'company_attribute',
        attribute_key: 'company',
        attribute_display_type: 'number',
      },
    ],
  };
  wrapper = make();
  expect(wrapper.vm.contactDefinitions.map(item => item.id)).toEqual([1]);
  expect(wrapper.vm.companyDefinitions.map(item => item.id)).toEqual([3]);
  expect(wrapper.vm.hasLegacy).toBe(true);
});
it('keeps the optional form usable after a failed preliminary lookup; server will validate on submit', async () => {
  wrapper = make({ name: 'Person', email: 'test@example.com' });
  ContactAPI.search.mockRejectedValue(new Error('Offline'));
  await wrapper.vm.lookupContact();
  await flushPromises();
  expect(wrapper.vm.lookupError).toBe(true);
  expect(wrapper.vm.canSave).toBe(true);
});
it('cannot switch company or reuse a contact while saving', async () => {
  wrapper = make({ name: 'Person' }, { disabled: true });
  wrapper.vm.setCompanyMode('new');
  await wrapper.vm.useContact({ id: 7 });
  expect(wrapper.vm.draft.companyMode).toBe('none');
  expect(wrapper.vm.draft.companyChosen).toBe(false);
  expect(ContactAPI.show).not.toHaveBeenCalled();
});
it('marks no company only after an explicit click', async () => {
  wrapper = make({ name: 'Person' });
  const noCompany = wrapper.find('[data-registration-company] button');
  expect(noCompany.attributes('aria-pressed')).toBe('false');
  expect(registrationPayload(wrapper.vm.draft)).not.toHaveProperty('company');
  await noCompany.trigger('click');
  await wrapper.vm.$nextTick();
  expect(noCompany.attributes('aria-pressed')).toBe('true');
  expect(registrationPayload(wrapper.vm.draft).company).toEqual({
    mode: 'none',
  });
});

it('keeps company address attributes and respects a typed contact key instead of duplicating a text input', () => {
  session.state.value = {
    error: false,
    configuration: {
      surfaces: {
        contact_details: { mode: 'custom', ids: [1] },
        company_details: { mode: 'custom', ids: [2] },
      },
    },
    definitions: [
      {
        id: 1,
        attribute_model: 'contact_attribute',
        attribute_key: 'job_title',
        attribute_display_name: 'Role confirmed',
        attribute_display_type: 'checkbox',
      },
      {
        id: 2,
        attribute_model: 'company_attribute',
        attribute_key: 'address',
        attribute_display_name: 'Company address',
        attribute_display_type: 'text',
      },
    ],
  };
  wrapper = make({
    jobTitle: 'Old text draft',
    contactAttributes: { job_title: false },
  });
  expect(wrapper.vm.nativeTextDetail('job_title')).toBe(false);
  expect(wrapper.vm.contactDefinitions.map(item => item.id)).toEqual([1]);
  expect(wrapper.vm.companyDefinitions.map(item => item.id)).toEqual([2]);
  expect(
    registrationPayload(wrapper.vm.draft).contact.custom_attributes.job_title
  ).toBe(false);
});

describe('composed payload', () => {
  it('preserves typed false and zero and excludes empty optional fields', () => {
    const payload = registrationPayload({
      ...newRegistrationDraft(),
      name: ' Person ',
      contactAttributes: { count: 0, enabled: false, unused: '' },
      companyMode: 'new',
      companyName: ' Company ',
      companyAttributes: { count: 0, enabled: false },
    });
    expect(payload.contact).toEqual({
      name: 'Person',
      additional_attributes: {},
      custom_attributes: { count: 0, enabled: false },
    });
    expect(payload.company.attributes.custom_attributes).toEqual({
      count: 0,
      enabled: false,
    });
    expect(payload.company.attributes).not.toHaveProperty('domain');
  });
  it('omits company when no company option was chosen, keeping native email-domain association', () => {
    const payload = registrationPayload({
      ...newRegistrationDraft(),
      name: 'Person',
      company: { id: 8 },
      companyName: 'Stale',
      companyAttributes: { old: true },
    });
    expect(payload).not.toHaveProperty('company');
  });
  it('sends an explicit no-company choice without stale company values', () => {
    const payload = registrationPayload({
      ...newRegistrationDraft(),
      name: 'Person',
      companyChosen: true,
      company: { id: 8 },
      companyName: 'Stale',
      companyAttributes: { old: true },
    });
    expect(payload.company).toEqual({ mode: 'none' });
  });
  it('keeps only the company ID when an existing company is selected', () => {
    expect(
      registrationPayload({
        ...newRegistrationDraft(),
        name: 'Person',
        companyMode: 'existing',
        company: { id: 8 },
        companyName: 'Not saved',
      }).company
    ).toEqual({ mode: 'existing', id: 8 });
  });
  it.each([
    ['https://EXAMPLE.com/path', 'example.com'],
    [' example.com. ', 'example.com'],
    ['', ''],
    ['bad domain', ''],
    ['https://user:secret@example.com', ''],
    ['ftp://example.com', ''],
  ])('normalizes domain %s as %s', (input, output) =>
    expect(companyDomain(input)).toBe(output)
  );
});
