import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { CONTACT_PERMISSIONS } from 'dashboard/constants/permissions';

// UX counterpart of Relationships::RecordPermissions. CRM card management
// never grants shared-record writes. The server remains the authority.
export function useRelationshipPermissions() {
  const getters = useStoreGetters();
  const canManageRelationshipRecords = computed(() => {
    const role = getters.getCurrentRole.value;
    const customRoleId = getters.getCurrentCustomRoleId.value;
    if (role === 'administrator') return true;
    if (role === 'agent' && !customRoleId) return true;
    if (!customRoleId) return false;
    const user = getters.getCurrentUser.value;
    return Boolean(
      user?.accounts &&
        getUserPermissions(user, getters.getCurrentAccountId.value).includes(
          CONTACT_PERMISSIONS
        )
    );
  });
  return { canManageRelationshipRecords };
}
