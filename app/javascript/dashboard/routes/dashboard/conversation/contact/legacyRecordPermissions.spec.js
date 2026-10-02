import { ref, nextTick } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContactInfo from './ContactInfo.vue';
import ContactInfoRow from './ContactInfoRow.vue';
import EditContact from './EditContact.vue';
import ContactForm from './ContactForm.vue';
import ContactNotes from './ContactNotes.vue';
import CustomAttributes from '../customAttributes/CustomAttributes.vue';

const canManage = ref(false);
const attributesEnabled = ref(false);
const keyboardBindings = [];
const record = {
  id: 12,
  name: 'Mariana',
  email: 'mariana@example.test',
  additional_attributes: {},
  custom_attributes: { seats: 0, active: false },
};
const definitions = [
  {
    id: 1,
    attribute_model: 'contact_attribute',
    attribute_key: 'seats',
    attribute_display_name: 'Seats',
    attribute_display_type: 'number',
  },
  {
    id: 2,
    attribute_model: 'contact_attribute',
    attribute_key: 'active',
    attribute_display_name: 'Active',
    attribute_display_type: 'checkbox',
  },
];
vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({
    canManageRelationshipRecords: canManage,
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(false) }),
}));
vi.mock('shared/composables/useExactTimestamp', () => ({
  useExactTimestamp: () => () => 'date',
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => keyboardBindings.push(events),
}));
vi.mock('dashboard/composables/useFixedPanelState', () => ({
  useFixedPanelPresence: () => {},
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, contactId: 12 } }),
}));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({
    attributesEnabled,
    accountId: ref(1),
    state: ref({
      definitions,
      configuration: {
        surfaces: {
          contact_sidebar: { mode: 'custom', ids: [1, 2] },
        },
      },
    }),
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({}), updateUISettings: vi.fn() }),
}));

const wrappers = [];
function mountPanel(component, props = {}) {
  const store = createStore({
    getters: {
      'contacts/getUIFlags': () => ({}),
      getSelectedChat: () => ({
        id: 9,
        meta: { sender: { id: 12 } },
        custom_attributes: { seats: 0, active: false },
      }),
      getCurrentUser: () => ({ id: 1 }),
      getCurrentAccountId: () => 1,
      'contactNotes/getUIFlags': () => ({}),
      'contactNotes/getAllNotesByContactId': () => () => [
        { id: 3, content: 'Preserve note', user: { id: 1 } },
      ],
      'contacts/getContact': () => () => record,
      'attributes/getAttributesByModel': () => () => definitions,
    },
  });
  const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue({});
  const wrapper = shallowMount(component, {
    props,
    global: {
      plugins: [store],
      mocks: { $route: { params: { accountId: 1 } } },
      stubs: {
        transition: { template: '<div><slot /></div>' },
        InlineInput: {
          name: 'InlineInput',
          template: '<input />',
          methods: { focus: vi.fn() },
        },
        Draggable: {
          props: ['list'],
          template:
            '<div><slot v-for="item in list" name="item" :element="item" /></div>',
        },
      },
    },
  });
  wrappers.push(wrapper);
  return { wrapper, dispatch };
}
beforeEach(() => {
  canManage.value = false;
  attributesEnabled.value = false;
  keyboardBindings.length = 0;
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('shows contact data and navigation without inline editors, merge or edit drawer for a record reader', async () => {
  const { wrapper, dispatch } = mountPanel(ContactInfo, { contact: record });
  expect(wrapper.text()).toContain('Mariana');
  expect(wrapper.find('a[target="_blank"]').attributes('href')).toContain(
    '/contacts/12'
  );
  expect(
    wrapper
      .findAllComponents(ContactInfoRow)
      .every(item => !item.props('editable'))
  ).toBe(true);
  expect(wrapper.findComponent({ name: 'ContactMergeModal' }).exists()).toBe(
    false
  );
  expect(wrapper.findComponent(EditContact).exists()).toBe(false);
  dispatch.mockClear();
  await wrapper.vm.updateContactField({ name: 'Forbidden' });
  wrapper.vm.startEditingName();
  expect(dispatch).not.toHaveBeenCalled();
  expect(wrapper.vm.isEditingName).toBe(false);
});

it('keeps contact writers enabled and rechecks permission before an inline save', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = mountPanel(ContactInfo, { contact: record });
  expect(
    wrapper
      .findAllComponents(ContactInfoRow)
      .filter(item => item.props('editable'))
  ).toHaveLength(3);
  await wrapper.vm.updateContactField({ name: 'Mariana updated' });
  expect(dispatch).toHaveBeenCalledWith('contacts/update', {
    id: 12,
    name: 'Mariana updated',
  });
  wrapper.vm.startEditingName();
  wrapper.vm.editName = 'Draft after revocation';
  canManage.value = false;
  await nextTick();
  dispatch.mockClear();
  await wrapper.vm.saveNameEdit();
  expect(dispatch).not.toHaveBeenCalled();
  expect(wrapper.findComponent(EditContact).exists()).toBe(false);
});

it('does not mount the legacy contact form when permission was revoked while its drawer was open', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = mountPanel(EditContact, {
    show: true,
    contact: record,
  });
  const form = wrapper.findComponent(ContactForm);
  expect(form.exists(), wrapper.html()).toBe(true);
  const submit = form.props('onSubmit');
  canManage.value = false;
  await nextTick();
  expect(wrapper.findComponent(ContactForm).exists()).toBe(false);
  dispatch.mockClear();
  await expect(submit({ id: 12, name: 'Forbidden' })).rejects.toThrow();
  expect(dispatch).not.toHaveBeenCalled();
});

it('keeps saved contact notes readable without creation or deletion controls', async () => {
  const { wrapper, dispatch } = mountPanel(ContactNotes, { contactId: 12 });
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith('contactNotes/get', { contactId: 12 });
  expect(
    wrapper.findComponent({ name: 'ContactNoteItem' }).props('allowDelete')
  ).toBe(false);
  expect(
    wrapper
      .findAllComponents({ name: 'Button' })
      .some(
        button =>
          button.props('label') === 'CONTACTS_LAYOUT.SIDEBAR.NOTES.ADD_NOTE'
      )
  ).toBe(false);
  dispatch.mockClear();
  wrapper.vm.onDelete(3);
  wrapper.vm.openCreateModal();
  expect(dispatch).not.toHaveBeenCalled();
  expect(wrapper.vm.shouldShowCreateModal).toBe(false);
});

it('blocks the note shortcut and stale delete event after record permission is revoked', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = mountPanel(ContactNotes, { contactId: 12 });
  wrapper.vm.openCreateModal();
  wrapper.vm.noteContent = 'Draft note';
  canManage.value = false;
  await nextTick();
  dispatch.mockClear();
  await keyboardBindings
    .find(item => item['$mod+Enter'])
    ['$mod+Enter'].action();
  wrapper.vm.onDelete(3);
  expect(dispatch).not.toHaveBeenCalled();
});

it('preserves authorized note creation', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = mountPanel(ContactNotes, { contactId: 12 });
  wrapper.vm.openCreateModal();
  wrapper.vm.noteContent = 'Authorized note';
  await wrapper.vm.onAdd();
  expect(dispatch).toHaveBeenCalledWith('contactNotes/create', {
    contactId: 12,
    content: 'Authorized note',
  });
});

it('renders legacy contact attributes as read-only fields and blocks emitted writes', async () => {
  const { wrapper, dispatch } = mountPanel(CustomAttributes, {
    attributeType: 'contact_attribute',
    contactId: 12,
    attributeFrom: 'conversation_contact_panel',
  });
  const fields = wrapper.findAllComponents({ name: 'FieldEditor' });
  expect(fields).toHaveLength(2);
  expect(fields.every(field => field.props('readOnly'))).toBe(true);
  expect(fields[0].props('record').custom_attributes.seats).toBe(0);
  expect(fields[1].props('record').custom_attributes.active).toBe(false);
  dispatch.mockClear();
  await wrapper.vm.onUpdate('seats', 5);
  await wrapper.vm.onDelete('active');
  expect(dispatch).not.toHaveBeenCalled();
});

it('keeps the new attribute surface read-only without changing its selected fields', async () => {
  attributesEnabled.value = true;
  const { wrapper, dispatch } = mountPanel(CustomAttributes, {
    attributeType: 'contact_attribute',
    contactId: 12,
    attributeFrom: 'conversation_contact_panel',
  });
  const fields = wrapper.findAllComponents({ name: 'FieldEditor' });
  expect(fields.map(field => field.props('definition').id)).toEqual([1, 2]);
  expect(fields.every(field => field.props('readOnly'))).toBe(true);
  dispatch.mockClear();
  await wrapper.vm.onUpdate('active', true);
  expect(dispatch).not.toHaveBeenCalled();
});

it('does not save a stale inline field after editability is revoked', async () => {
  const { wrapper } = mountPanel(ContactInfoRow, {
    editable: true,
    value: 'Original',
    emoji: '',
    icon: 'mail',
  });
  wrapper.vm.startEditing();
  wrapper.vm.editValue = 'Draft';
  await wrapper.setProps({ editable: false });
  wrapper.vm.saveEdit();
  expect(wrapper.emitted('update')).toBeUndefined();
});

it('keeps conversation attributes independent from shared-contact write permission', async () => {
  const { wrapper, dispatch } = mountPanel(CustomAttributes, {
    attributeType: 'conversation_attribute',
    attributeFrom: 'conversation',
  });
  dispatch.mockClear();
  await wrapper.vm.onUpdate('seats', 5);
  expect(dispatch).toHaveBeenCalledWith('updateCustomAttributes', {
    conversationId: 9,
    customAttributes: { seats: 5, active: false },
  });
});

it('keeps contact attribute updates available to the record manager', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = mountPanel(CustomAttributes, {
    attributeType: 'contact_attribute',
    contactId: 12,
    attributeFrom: 'conversation_contact_panel',
  });
  dispatch.mockClear();
  await wrapper.vm.onUpdate('seats', 5);
  expect(dispatch).toHaveBeenCalledWith('contacts/update', {
    id: 12,
    customAttributes: { seats: 5 },
  });
});
