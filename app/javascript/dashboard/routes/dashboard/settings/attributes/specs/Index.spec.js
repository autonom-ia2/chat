import { mount, flushPromises } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import Index from '../Index.vue';
import AddAttribute from '../AddAttribute.vue';

const testState = vi.hoisted(() => ({
  companiesEnabled: true,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(16),
    currentAccount: { value: { id: 16, settings: {} } },
    isCloudFeatureEnabled: feature =>
      feature === 'companies' && testState.companiesEnabled,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: vi.fn(),
    subscribe: vi.fn(),
    getters: { getCurrentUserID: 1 },
  }),
  useMapGetter: () => ({ value: [] }),
  useStoreGetters: () => ({
    'attributes/getUIFlags': {
      value: {
        isFetching: false,
        isCreating: false,
        isUpdating: false,
        isDeleting: false,
      },
    },
    'attributes/getAttributesByModel': {
      value: model =>
        [
          {
            id: 1,
            attribute_model: 'conversation_attribute',
            attribute_display_name: 'Conversation field',
          },
          {
            id: 2,
            attribute_model: 'contact_attribute',
            attribute_display_name: 'Contact field',
          },
          {
            id: 3,
            attribute_model: 'company_attribute',
            attribute_display_name: 'Company field',
          },
        ].filter(item => item.attribute_model === model),
    },
  }),
}));

const mountIndex = async () => {
  const wrapper = mount(Index, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: {
          template: '<div><slot name="tabs" /><slot name="actions" /></div>',
        },
        TabBar: {
          props: ['tabs'],
          emits: ['tabChanged'],
          template: `
            <div>
              <button
                v-for="tab in tabs"
                :key="tab.key"
                class="tab"
                :data-tab="tab.key"
                @click="$emit('tabChanged', tab)"
              >
                {{ tab.label }}
              </button>
            </div>
          `,
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template:
            '<button class="create-attribute" @click="$emit(\'click\')">{{ label }}</button>',
        },
        AttributeListItem: {
          props: ['attribute'],
          template:
            '<div class="attribute-item">{{ attribute.attribute_model }}</div>',
        },
        AddAttribute: {
          props: ['selectedAttributeModelTab', 'showCompanyModel'],
          template:
            '<div class="add-attribute" :data-selected="selectedAttributeModelTab" :data-company="String(showCompanyModel)" />',
        },
        EditAttribute: true,
        'woot-confirm-delete-modal': true,
      },
    },
  });

  await flushPromises();
  return wrapper;
};

describe('Custom attributes settings - company model', () => {
  beforeEach(() => {
    testState.companiesEnabled = true;
  });

  it('exposes Company as the third tab when Companies is enabled', async () => {
    const wrapper = await mountIndex();

    expect(wrapper.find('[data-tab="0"]').exists()).toBe(true);
    expect(wrapper.find('[data-tab="1"]').exists()).toBe(true);
    expect(wrapper.find('[data-tab="2"]').exists()).toBe(true);

    await wrapper.find('[data-tab="2"]').trigger('click');
    await nextTick();

    expect(wrapper.find('.attribute-item').text()).toBe('company_attribute');
  });

  it('keeps Company unavailable when the Companies feature is disabled', async () => {
    testState.companiesEnabled = false;
    const wrapper = await mountIndex();

    expect(wrapper.find('[data-tab="0"]').exists()).toBe(true);
    expect(wrapper.find('[data-tab="1"]').exists()).toBe(true);
    expect(wrapper.find('[data-tab="2"]').exists()).toBe(false);
  });

  it('filters the Company model from the create form when not allowed', () => {
    const withoutCompany = AddAttribute.computed.models.call({
      showCompanyModel: false,
      $t: key => key,
    });
    const withCompany = AddAttribute.computed.models.call({
      showCompanyModel: true,
      $t: key => key,
    });

    expect(withoutCompany.map(item => item.key)).toEqual([
      'CONVERSATION',
      'CONTACT',
    ]);
    expect(withCompany.map(item => item.key)).toEqual([
      'CONVERSATION',
      'CONTACT',
      'COMPANY',
    ]);
  });
});
