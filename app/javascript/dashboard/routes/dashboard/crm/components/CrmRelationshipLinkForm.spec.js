import { mount, flushPromises } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmRelationshipLinkForm from './CrmRelationshipLinkForm.vue';

vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { createCardContact: vi.fn(), linkCardContact: vi.fn() },
}));
const makeForm = (mode = 'new') =>
  mount(CrmRelationshipLinkForm, {
    props: { cardId: 5, mode },
    global: { stubs: { Avatar: true, PhoneNumberInput: true } },
  });
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  CrmKanbanAPI.createCardContact.mockResolvedValue({
    data: { payload: { id: 5, contact_id: 42 } },
  });
  CrmKanbanAPI.linkCardContact.mockResolvedValue({
    data: { payload: { id: 5, contact_id: 42 } },
  });
  ContactAPI.search.mockResolvedValue({
    data: { payload: [{ id: 42, name: 'Mariana' }] },
  });
});
afterEach(() => {
  wrapper?.unmount();
});

it('creates the contact on the current card with an idempotency key', async () => {
  wrapper = makeForm();
  wrapper.vm.form.name = '  Mariana  ';
  await wrapper.vm.save();
  const [id, payload, key] = CrmKanbanAPI.createCardContact.mock.lastCall;
  expect(id).toBe(5);
  expect(payload).toEqual({ name: 'Mariana', email: '', phone_number: '' });
  expect(key).toBeTruthy();
  expect(wrapper.emitted('saved')[0][0].id).toBe(5);
});
it('does not invent a telephone when the native phone input clears to null', async () => {
  wrapper = makeForm();
  Object.assign(wrapper.vm.form, { name: 'Name only', phone_number: null });
  await wrapper.vm.save();
  expect(CrmKanbanAPI.createCardContact.mock.lastCall[1].phone_number).toBe('');
});
it('blocks an empty name without sending a request', async () => {
  wrapper = makeForm();
  wrapper.vm.form.name = '   ';
  await wrapper.vm.save();
  expect(CrmKanbanAPI.createCardContact).not.toHaveBeenCalled();
});
it('retains the same request key and draft when retrying a failed request', async () => {
  CrmKanbanAPI.createCardContact.mockRejectedValue(new Error('network failed'));
  wrapper = makeForm();
  wrapper.vm.form.name = 'Mariana';
  await wrapper.vm.save();
  await wrapper.vm.save();
  expect(CrmKanbanAPI.createCardContact.mock.calls[0][2]).toBe(
    CrmKanbanAPI.createCardContact.mock.calls[1][2]
  );
  expect(wrapper.vm.form.name).toBe('Mariana');
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
});
it('uses a new key when the failed payload is explicitly corrected', async () => {
  CrmKanbanAPI.createCardContact.mockRejectedValue(new Error('failed'));
  wrapper = makeForm();
  wrapper.vm.form.name = 'Mariana';
  await wrapper.vm.save();
  wrapper.vm.form.email = 'new@example.com';
  await wrapper.vm.save();
  expect(CrmKanbanAPI.createCardContact.mock.calls[0][2]).not.toBe(
    CrmKanbanAPI.createCardContact.mock.calls[1][2]
  );
});
it('blocks duplicate submit while the first request is pending', async () => {
  let resolveSave;
  CrmKanbanAPI.createCardContact.mockImplementation(
    () =>
      new Promise(resolve => {
        resolveSave = resolve;
      })
  );
  wrapper = makeForm();
  wrapper.vm.form.name = 'Mariana';
  const saving = wrapper.vm.save();
  await wrapper.vm.save();
  expect(CrmKanbanAPI.createCardContact).toHaveBeenCalledTimes(1);
  resolveSave({ data: { payload: { id: 5 } } });
  await saving;
});
it('links only the selected ID rather than copying the found contact', async () => {
  wrapper = makeForm('existing');
  wrapper.vm.query = 'Mariana';
  await wrapper.vm.search();
  wrapper.vm.selected = wrapper.vm.results[0];
  await wrapper.vm.save();
  expect(CrmKanbanAPI.linkCardContact).toHaveBeenCalledWith(5, 42);
  expect(CrmKanbanAPI.createCardContact).not.toHaveBeenCalled();
});
it('does not submit an existing-contact flow without a selection', async () => {
  wrapper = makeForm('existing');
  await wrapper.vm.save();
  expect(CrmKanbanAPI.linkCardContact).not.toHaveBeenCalled();
});
it('does not expose server details in a conflict message', async () => {
  CrmKanbanAPI.createCardContact.mockRejectedValue({
    response: { status: 422, data: { message: 'Private account details' } },
  });
  wrapper = makeForm();
  wrapper.vm.form.name = 'Mariana';
  await wrapper.vm.save();
  expect(wrapper.text()).toContain('SAVE_CONFLICT');
  expect(wrapper.text()).not.toContain('Private account details');
});
it('ignores stale search responses', async () => {
  let resolveOld;
  ContactAPI.search.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  wrapper = makeForm('existing');
  wrapper.vm.query = 'Old';
  const oldSearch = wrapper.vm.search();
  wrapper.vm.query = 'Mariana';
  await wrapper.vm.search();
  resolveOld({ data: { payload: [{ id: 99, name: 'Stale' }] } });
  await oldSearch;
  await flushPromises();
  expect(wrapper.vm.results[0].id).toBe(42);
});
// #2111: o telefone usava o PhoneNumberInput compacto (h-8, 32 px) ao lado de nome e e-mail em h-10 (40 px).
// O jsdom não calcula CSS: a prova aqui é a classe de altura; a medida em pixels está no print do PR.
it('gives the phone box the same height class as the e-mail box', () => {
  wrapper = mount(CrmRelationshipLinkForm, {
    props: { cardId: 5, mode: 'new' },
    global: {
      stubs: { Avatar: true },
      directives: { 'on-clickaway': {} },
    },
  });
  const heightOf = element =>
    [...element.classList].filter(name => name.startsWith('h-'));
  const email = wrapper.find('input[type="email"]').element;
  const phoneBox = wrapper
    .find('input[type="tel"]')
    .element.parentElement.closest('.outline');
  expect(heightOf(email)).toEqual(['h-10']);
  expect(heightOf(phoneBox)).toEqual(heightOf(email));
});
