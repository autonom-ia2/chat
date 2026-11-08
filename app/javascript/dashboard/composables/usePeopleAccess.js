import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import { PEOPLE_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import {
  holdsKey,
  keyLockReason,
  memberLockReason,
  reachesRole,
  roleLockReason,
} from 'dashboard/helper/peopleAccess';

const INBOX_MANAGE_PERMISSION = 'inbox_manage';

// What the current seat may do with people, teams and custom roles (#1931). The rules live in
// helper/peopleAccess.js; this only feeds them the current seat and the account's custom roles.
export function usePeopleAccess() {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  const currentRole = useMapGetter('getCurrentRole');
  const customRoleId = useMapGetter('getCurrentCustomRoleId');
  const customRoles = useMapGetter('customRole/getCustomRoles');

  const giver = computed(() => ({
    userId: currentUser.value?.id,
    isAdmin: currentRole.value === 'administrator',
    customRoleId: customRoleId.value || null,
    permissions: getUserPermissions(currentUser.value, accountId.value),
  }));

  const holds = key => computed(() => holdsKey(giver.value, key));

  return {
    // Quem está montando, para as regras que pedem o lugar inteiro (motivoDaTrava, alcance antes de salvar).
    giver,
    isAdmin: computed(() => giver.value.isAdmin),
    canManagePeople: holds(PEOPLE_MANAGE_PERMISSION),
    canManageInboxes: holds(INBOX_MANAGE_PERMISSION),
    reachesRole: role => reachesRole(giver.value, role),
    memberLockReason: agent =>
      memberLockReason(giver.value, agent, customRoles.value),
    canTouchMember: agent =>
      !memberLockReason(giver.value, agent, customRoles.value),
    roleLockReason: role => roleLockReason(giver.value, role),
    keyLockReason: key => keyLockReason(giver.value, key),
  };
}
