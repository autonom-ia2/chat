import { usePeopleAccess } from '../usePeopleAccess';
import { useMapGetter } from 'dashboard/composables/store';
import { ref } from 'vue';

vi.mock('dashboard/composables/store');

const seat = ({ role = 'agent', customRoleId = null, permissions = [] }) => {
  const getters = {
    getCurrentUser: {
      id: 2,
      accounts: [{ id: 1, permissions, custom_role_id: customRoleId }],
    },
    getCurrentAccountId: 1,
    getCurrentRole: role,
    getCurrentCustomRoleId: customRoleId,
    'customRole/getCustomRoles': [
      { id: 10, permissions },
      { id: 20, permissions: ['inbox_manage'] },
    ],
  };
  useMapGetter.mockImplementation(key => ref(getters[key]));
  return usePeopleAccess();
};

describe('usePeopleAccess', () => {
  it('gives an administrator every power', () => {
    const access = seat({
      role: 'administrator',
      permissions: ['administrator'],
    });
    expect(access.isAdmin.value).toBe(true);
    expect(access.canManagePeople.value).toBe(true);
    expect(access.canManageInboxes.value).toBe(true);
  });

  it('reads the keys of the current custom role', () => {
    const access = seat({
      customRoleId: 10,
      permissions: ['people_manage', 'contact_manage', 'custom_role'],
    });
    expect(access.isAdmin.value).toBe(false);
    expect(access.canManagePeople.value).toBe(true);
    expect(access.canManageInboxes.value).toBe(false);
  });

  it('checks members against the account custom roles', () => {
    const access = seat({
      customRoleId: 10,
      permissions: ['people_manage', 'custom_role'],
    });
    expect(access.canTouchMember({ id: 3, role: 'agent' })).toBe(true);
    expect(
      access.canTouchMember({ id: 4, role: 'agent', custom_role_id: 20 })
    ).toBe(false);
    expect(access.memberLockReason({ id: 2, role: 'agent' })).toBe('SELF');
    expect(access.roleLockReason({ id: 10, permissions: [] })).toBe('MINE');
  });
});
