import { mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import CrmRelationshipResources from './CrmRelationshipResources.vue';

const controls = vi.hoisted(() => ({ open: vi.fn(), reset: vi.fn() }));
const attributesEnabled = ref(true);
const mediaEnabled = ref(true);
const companiesEnabled = ref(true);
const fieldDirty = ref(false);
const fieldBusy = ref(false);
const state = reactive({
  definitions: [],
  configuration: null,
  can_manage: true,
  error: false,
  loading: false,
});
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({
    attributesEnabled,
    mediaEnabled,
    companiesEnabled,
    accountId: ref(1),
    state: ref(state),
    load: vi.fn(),
  }),
}));
const FieldStub = {
  props: {
    definition: Object,
    record: Object,
    entity: String,
    readOnly: Boolean,
  },
  setup(_, { expose }) {
    expose({ dirty: fieldDirty, busy: fieldBusy, reset: controls.reset });
    return {};
  },
  template: '<div data-field>{{ definition.attribute_display_name }}</div>',
};
const ConfigStub = {
  props: { surface: String, entity: String, showActions: Boolean },
  setup(_, { expose }) {
    expose({ open: controls.open });
  },
  template: '<div data-config />',
};
const makeResources = (props = {}) =>
  mount(CrmRelationshipResources, {
    props: {
      contact: { id: 42 },
      company: { id: 7 },
      canManage: true,
      onGuard: action => action(),
      ...props,
    },
    global: {
      stubs: {
        FieldEditor: FieldStub,
        FieldConfigurator: ConfigStub,
        RelationshipMedia: true,
      },
    },
  });
const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  attributesEnabled.value = true;
  mediaEnabled.value = true;
  companiesEnabled.value = true;
  fieldDirty.value = false;
  fieldBusy.value = false;
  Object.assign(state, {
    can_manage: true,
    error: false,
    loading: false,
    definitions: [
      {
        id: 1,
        attribute_key: 'segment',
        attribute_display_name: 'Segmento',
        attribute_model: 'contact_attribute',
      },
      {
        id: 2,
        attribute_key: 'hidden',
        attribute_display_name: 'Oculto',
        attribute_model: 'contact_attribute',
      },
      {
        id: 3,
        attribute_key: 'size',
        attribute_display_name: 'Porte',
        attribute_model: 'company_attribute',
      },
    ],
    configuration: {
      surfaces: {
        contact_details: { mode: 'custom', ids: [1] },
        contact_sidebar: { mode: 'custom', ids: [2] },
        company_details: { mode: 'custom', ids: [3] },
      },
    },
  });
});
afterEach(() => wrapper?.unmount());

it('does not mount media or editable values before expansion', () => {
  wrapper = makeResources();
  expect(wrapper.findAllComponents(FieldStub)).toHaveLength(0);
  expect(wrapper.findComponent({ name: 'RelationshipMedia' }).exists()).toBe(
    false
  );
});
it('uses contact detail selection rather than overwriting the conversation sidebar', async () => {
  wrapper = makeResources();
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  expect(wrapper.findAll('[data-field]').map(field => field.text())).toEqual([
    'Segmento',
  ]);
  expect(wrapper.findComponent(ConfigStub).props('surface')).toBe(
    'contact_details'
  );
  expect(state.configuration.surfaces.contact_sidebar.ids).toEqual([2]);
});
it('switches to the canonical company and company selection through the draft guard', async () => {
  wrapper = makeResources();
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.FIELDS_COMPANY').trigger(
    'click'
  );
  expect(wrapper.emitted('guard')).toHaveLength(1);
  expect(wrapper.findComponent(FieldStub).props('record').id).toBe(7);
  expect(wrapper.findComponent(ConfigStub).props('surface')).toBe(
    'company_details'
  );
  expect(wrapper.findAll('[data-field]').map(field => field.text())).toEqual([
    'Porte',
  ]);
});
it('cannot lose a field draft by collapsing before approval', async () => {
  wrapper = makeResources({ onGuard: () => {} });
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  fieldDirty.value = true;
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  expect(wrapper.vm.dirty).toBe(true);
  expect(wrapper.find('[data-field]').exists()).toBe(true);
  wrapper.emitted('guard')[0][0]();
  await wrapper.vm.$nextTick();
  expect(wrapper.find('[data-field]').exists()).toBe(false);
});
it('propagates pending saves and only exposes field reset, not a new save operation', async () => {
  wrapper = makeResources();
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  fieldBusy.value = true;
  expect(wrapper.vm.saving).toBe(true);
  wrapper.vm.reset();
  expect(controls.reset).toHaveBeenCalled();
});
it('opens the shared configurator only through the guard', async () => {
  wrapper = makeResources({ onGuard: () => {} });
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  await button(wrapper, 'RELATIONSHIPS.CONFIGURE').trigger('click');
  expect(controls.open).not.toHaveBeenCalled();
  wrapper.emitted('guard')[0][0]();
  expect(controls.open).toHaveBeenCalledOnce();
});
it('propagates read-only access and does not offer global configuration to an agent', async () => {
  state.can_manage = false;
  wrapper = makeResources({ canManage: false });
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  expect(wrapper.findComponent(FieldStub).props('readOnly')).toBe(true);
  expect(button(wrapper, 'RELATIONSHIPS.CONFIGURE')).toBeUndefined();
});
it('does not show company resources without a canonical company link', async () => {
  wrapper = makeResources({ company: null });
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  expect(
    button(wrapper, 'CRM_KANBAN.RELATIONSHIP.FIELDS_COMPANY')
  ).toBeUndefined();
});
it('respects separate feature switches', async () => {
  attributesEnabled.value = false;
  wrapper = makeResources();
  expect(wrapper.find('[data-crm-fields]').exists()).toBe(false);
  expect(wrapper.find('[data-crm-media]').exists()).toBe(true);
  mediaEnabled.value = false;
  await wrapper.vm.$nextTick();
  expect(wrapper.find('[data-crm-media]').exists()).toBe(false);
});
it('opens the scoped native media component and expands in place', async () => {
  wrapper = makeResources();
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.MEDIA').trigger('click');
  let media = wrapper.findComponent({ name: 'RelationshipMedia' });
  expect(media.props()).toMatchObject({
    contactId: 42,
    companyId: null,
    expanded: false,
    embedded: true,
  });
  media.vm.$emit('expand');
  await wrapper.vm.$nextTick();
  expect(media.props('expanded')).toBe(true);
  await wrapper
    .find('[data-crm-media]')
    .findAll('button')
    .find(item => item.text() === 'CRM_KANBAN.RELATIONSHIP.FIELDS_COMPANY')
    .trigger('click');
  media = wrapper.findComponent({ name: 'RelationshipMedia' });
  expect(media.props()).toMatchObject({
    contactId: null,
    companyId: 7,
    expanded: false,
    embedded: true,
  });
});
it('removes fields on a configuration authorization error instead of displaying stale values', async () => {
  wrapper = makeResources();
  await button(wrapper, 'CRM_KANBAN.RELATIONSHIP.ATTRIBUTES').trigger('click');
  expect(wrapper.find('[data-field]').exists()).toBe(true);
  state.error = true;
  await wrapper.vm.$nextTick();
  expect(wrapper.find('[data-field]').exists()).toBe(false);
});
