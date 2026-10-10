import { flushPromises, mount } from '@vue/test-utils';
import CrmCardCustomFields from './CrmCardCustomFields.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';
import ListAttribute from 'dashboard/components-next/CustomAttributes/ListAttribute.vue';
import CheckboxAttribute from 'dashboard/components-next/CustomAttributes/CheckboxAttribute.vue';

const { store, alertSpy } = vi.hoisted(() => ({
  store: { getters: {}, dispatch: vi.fn() },
  alertSpy: vi.fn(),
}));

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => store,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alertSpy }));

const definitions = [
  {
    id: 1,
    attributeKey: 'plan',
    attributeDisplayName: 'Plano',
    attributeDisplayType: 'list',
    attributeValues: ['Básico', 'Pro'],
    attributeModel: 'card_attribute',
  },
  {
    id: 2,
    attributeKey: 'seats',
    attributeDisplayName: 'Licenças',
    attributeDisplayType: 'number',
    attributeModel: 'card_attribute',
  },
  {
    id: 3,
    attributeKey: 'signed',
    attributeDisplayName: 'Contrato assinado',
    attributeDisplayType: 'checkbox',
    attributeModel: 'card_attribute',
  },
];

const card = {
  id: 42,
  custom_attributes: { plan: 'Básico', seats: 3, signed: true },
};

const mountFields = (props = {}) =>
  mount(CrmCardCustomFields, {
    props: { card, canManage: true, ...props },
    global: {
      stubs: { 'router-link': { props: ['to'], template: '<a><slot /></a>' } },
      directives: { onClickaway: {} },
    },
  });

const setGetters = ({ defs = definitions, role = 'agent' } = {}) => {
  store.getters = {
    'attributes/getCardAttributes': defs,
    getCurrentRole: role,
    getCurrentUser: { accounts: [{ id: 7, permissions: [] }] },
    getCurrentAccountId: 7,
  };
};

describe('CrmCardCustomFields', () => {
  beforeEach(() => {
    store.dispatch = vi.fn().mockResolvedValue({
      id: 42,
      custom_attributes: { plan: 'Pro', seats: 3, signed: true },
    });
    alertSpy.mockClear();
    setGetters();
  });

  it('lists every card definition with the value stored on the card', () => {
    const wrapper = mountFields();

    const rows = wrapper.findAll('[data-field]');
    expect(rows.map(row => row.attributes('data-field'))).toEqual([
      'plan',
      'seats',
      'signed',
    ]);
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Plano');
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Básico');
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Básico'
    );
    expect(wrapper.findComponent(OtherAttribute).props('attribute').value).toBe(
      3
    );
    expect(
      wrapper.findComponent(CheckboxAttribute).props('attribute').value
    ).toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('attributes/get');
  });

  it('saves only the edited key through crmKanban/updateCard', async () => {
    const wrapper = mountFields();

    wrapper.findComponent(ListAttribute).vm.$emit('update', 'Pro');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { plan: 'Pro' },
    });
    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_SUCCESS'
    );
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Pro'
    );
  });

  it('sends numbers as numbers and clears a field with null', async () => {
    const wrapper = mountFields();

    wrapper.findComponent(OtherAttribute).vm.$emit('update', '12');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { seats: 12 },
    });

    wrapper.findComponent(OtherAttribute).vm.$emit('delete');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('crmKanban/updateCard', {
      id: 42,
      custom_attributes: { seats: null },
    });
  });

  it('warns and keeps the value when the save fails', async () => {
    store.dispatch = vi.fn(action =>
      action === 'crmKanban/updateCard'
        ? Promise.reject(new Error('boom'))
        : Promise.resolve()
    );
    const wrapper = mountFields();

    wrapper.findComponent(ListAttribute).vm.$emit('update', 'Pro');
    await flushPromises();

    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_ERROR'
    );
    expect(wrapper.findComponent(ListAttribute).props('attribute').value).toBe(
      'Básico'
    );
  });

  it('is read-only without card permission', async () => {
    const wrapper = mountFields({ canManage: false });

    expect(wrapper.findComponent(ListAttribute).exists()).toBe(false);
    expect(wrapper.find('[data-field="plan"]').text()).toContain('Básico');
    expect(wrapper.find('[data-field="signed"]').text()).toContain(
      'CRM_KANBAN.RELATIONSHIP.VALUE_YES'
    );
  });

  it('shows the empty-state hint to admins when no card field exists', () => {
    setGetters({ defs: [], role: 'administrator' });
    const wrapper = mountFields();

    expect(
      wrapper.find('[data-testid="crm-card-custom-fields-empty"]').text()
    ).toContain('CRM_KANBAN.DRAWER.CARD_FIELDS.EMPTY_ADMIN');
    expect(
      wrapper.find('[data-testid="crm-card-custom-fields"]').isVisible()
    ).toBe(true);
  });

  it('hides the section for non-admins when no card field exists', () => {
    setGetters({ defs: [] });
    const wrapper = mountFields();

    expect(
      wrapper.find('[data-testid="crm-card-custom-fields"]').isVisible()
    ).toBe(false);
  });
});
