import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import {
  CONTACT_PERMISSIONS,
  CONTACT_VIEW_PERMISSION,
} from 'dashboard/constants/permissions';

const MANAGE_KEYS = [CONTACT_PERMISSIONS];
// Sem ver contatos, a conversa e o card mostram só nome, telefone e e-mail (#1849).
const VIEW_KEYS = [CONTACT_VIEW_PERMISSION, CONTACT_PERMISSIONS];

// UX counterpart of Relationships::RecordPermissions. CRM card management
// never grants shared-record writes. The server remains the authority.
// Recebe os getters já resolvidos (rootGetters de um store, ou valores do composable).
const grants = (getters, keys) => {
  const role = getters.getCurrentRole;
  const customRoleId = getters.getCurrentCustomRoleId;
  if (role === 'administrator') return true;
  if (role === 'agent' && !customRoleId) return true;
  if (!customRoleId) return false;
  const user = getters.getCurrentUser;
  if (!user?.accounts) return false;
  const permissions = getUserPermissions(user, getters.getCurrentAccountId);
  return keys.some(key => permissions.includes(key));
};

export const canViewRelationshipRecordsFrom = getters =>
  grants(getters, VIEW_KEYS);

export function useRelationshipPermissions() {
  const getters = useStoreGetters();
  const resolved = () => ({
    getCurrentRole: getters.getCurrentRole.value,
    getCurrentCustomRoleId: getters.getCurrentCustomRoleId.value,
    getCurrentUser: getters.getCurrentUser.value,
    getCurrentAccountId: getters.getCurrentAccountId.value,
  });
  const canManageRelationshipRecords = computed(() =>
    grants(resolved(), MANAGE_KEYS)
  );
  const canViewRelationshipRecords = computed(() =>
    grants(resolved(), VIEW_KEYS)
  );
  return { canManageRelationshipRecords, canViewRelationshipRecords };
}
