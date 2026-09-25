import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import {
  CRM_VIEW_PERMISSION,
  CRM_MANAGE_CARDS_PERMISSION,
  CRM_MOVE_CARDS_PERMISSION,
  CRM_MANAGE_PIPELINES_PERMISSION,
  CRM_MANAGE_AI_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
  CRM_ADMIN_PERMISSION,
  CRM_EXPORT_PERMISSION,
} from 'dashboard/constants/permissions.js';

/**
 * CRM permission computeds for UI gating.
 *
 * LOCKED PRODUCT DECISION ("if the admin granted it, the user has it"):
 * - Administrators get every CRM capability.
 * - Plain agents (a role, but NO custom_role) keep full CRM access too,
 *   preserving pre-PR14 behavior — granularity only applies to custom roles.
 * - Custom-role seats are gated by the granular crm_* keys (crm_admin implies all).
 *
 * Frontend gating is UX-only; Pundit policies are the real enforcement.
 */
export function useCrmPermissions() {
  const getters = useStoreGetters();

  const currentUser = computed(() => getters.getCurrentUser.value);
  const accountId = computed(() => getters.getCurrentAccountId.value);
  const role = computed(() => getters.getCurrentRole.value);
  const customRoleId = computed(() => getters.getCurrentCustomRoleId.value);

  const isAdmin = computed(() => role.value === 'administrator');
  // A seat that is not gated by a custom role keeps full CRM access.
  const isUngatedSeat = computed(() => isAdmin.value || !customRoleId.value);

  const permissions = computed(() =>
    getUserPermissions(currentUser.value, accountId.value)
  );

  const hasCrmPermission = key => {
    if (isUngatedSeat.value) return true;
    return (
      permissions.value.includes(CRM_ADMIN_PERMISSION) ||
      permissions.value.includes(key)
    );
  };

  const canViewCrm = computed(() => hasCrmPermission(CRM_VIEW_PERMISSION));
  const canManageCards = computed(() =>
    hasCrmPermission(CRM_MANAGE_CARDS_PERMISSION)
  );
  const canMoveCards = computed(
    () =>
      hasCrmPermission(CRM_MOVE_CARDS_PERMISSION) ||
      hasCrmPermission(CRM_MANAGE_CARDS_PERMISSION)
  );
  const canManagePipelines = computed(() =>
    hasCrmPermission(CRM_MANAGE_PIPELINES_PERMISSION)
  );
  const canManageAi = computed(() =>
    hasCrmPermission(CRM_MANAGE_AI_PERMISSION)
  );
  const canViewReports = computed(() =>
    hasCrmPermission(CRM_VIEW_REPORTS_PERMISSION)
  );
  // crm_admin is the only key that is NOT implied by an ungated seat being a
  // plain agent: admin-equivalent CRM actions (e.g. minting integration tokens)
  // require either the account administrator or the explicit crm_admin key.
  const canAdminCrm = computed(
    () => isAdmin.value || permissions.value.includes(CRM_ADMIN_PERMISSION)
  );
  // #722 — planilha da Lista é dado pessoal em lote: como canAdminCrm, o agente
  // sem função NÃO ganha por padrão (backend: crm_export em PLAIN_AGENT_DENIED_KEYS).
  const canExportCrm = computed(
    () => canAdminCrm.value || permissions.value.includes(CRM_EXPORT_PERMISSION)
  );

  return {
    canViewCrm,
    canManageCards,
    canMoveCards,
    canManagePipelines,
    canManageAi,
    canViewReports,
    canAdminCrm,
    canExportCrm,
  };
}
