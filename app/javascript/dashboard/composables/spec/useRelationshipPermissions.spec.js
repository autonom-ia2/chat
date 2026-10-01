import { computed, reactive } from 'vue';
import { useRelationshipPermissions } from '../useRelationshipPermissions';

const context = vi.hoisted(() => ({ state: null }));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({
    getCurrentRole: computed(() => context.state.role),
    getCurrentCustomRoleId: computed(() => context.state.customRoleId),
    getCurrentAccountId: computed(() => context.state.accountId),
    getCurrentUser: computed(() => ({ accounts: context.state.accounts })),
  }),
}));

beforeEach(() => {
  context.state = reactive({
    role: 'agent',
    customRoleId: 7,
    accountId: 1,
    accounts: [{ id: 1, permissions: ['contact_view', 'crm_view'] }],
  });
});

it.each([
  ['administrator', 7],
  ['administrator', null],
  ['agent', null],
])('preserves %s / custom role %s writes', (role, customRoleId) => {
  Object.assign(context.state, { role, customRoleId });
  expect(useRelationshipPermissions().canManageRelationshipRecords.value).toBe(
    true
  );
});
it.each(
  [
    ['contact_view'],
    ['crm_manage_cards'],
    ['crm_admin'],
    ['attribute_manage'],
    [],
  ].map(permissions => ({ permissions }))
)(
  'does not grant shared record writes from $permissions',
  ({ permissions }) => {
    context.state.accounts[0].permissions = permissions;
    expect(
      useRelationshipPermissions().canManageRelationshipRecords.value
    ).toBe(false);
  }
);
it('grants only the explicit record management key and reacts to revocation', () => {
  const permission = useRelationshipPermissions().canManageRelationshipRecords;
  context.state.accounts[0].permissions.push('contact_manage');
  expect(permission.value).toBe(true);
  context.state.accounts[0].permissions = ['contact_view'];
  expect(permission.value).toBe(false);
});
it('never carries a permission from another account', () => {
  context.state.accounts.push({ id: 2, permissions: ['contact_manage'] });
  const permission = useRelationshipPermissions().canManageRelationshipRecords;
  expect(permission.value).toBe(false);
  context.state.accountId = 2;
  expect(permission.value).toBe(true);
  context.state.accountId = 3;
  expect(permission.value).toBe(false);
});
it('fails closed for an unresolved seat', () => {
  context.state.role = undefined;
  context.state.customRoleId = undefined;
  expect(useRelationshipPermissions().canManageRelationshipRecords.value).toBe(
    false
  );
});
