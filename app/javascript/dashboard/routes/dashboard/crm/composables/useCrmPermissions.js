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
  CRM_DELETE_CARDS_PERMISSION,
} from 'dashboard/constants/permissions.js';

const SALES_VALUE_VIEW_KEY = 'sales_value_view';

// #2142 — espelho de PLAIN_AGENT_DENIED_KEYS (enterprise/app/policies/crm_permissions.rb):
// o agente sem função não ganha essas chaves; no OSS elas são só do administrador.
export const PLAIN_AGENT_DENIED_KEYS = [
  CRM_MANAGE_PIPELINES_PERMISSION,
  CRM_MANAGE_AI_PERMISSION,
  CRM_ADMIN_PERMISSION,
  CRM_EXPORT_PERMISSION,
];

/**
 * CRM permission computeds for UI gating.
 *
 * LOCKED PRODUCT DECISION ("if the admin granted it, the user has it"):
 * - Administrators get every CRM capability.
 * - Plain agents (a role, but NO custom_role) keep CRM access too, except the
 *   PLAIN_AGENT_DENIED_KEYS (pipelines, AI, crm_admin, export), as the server does.
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
  // A seat that is not gated by a custom role (admin or plain agent).
  const isUngatedSeat = computed(() => isAdmin.value || !customRoleId.value);

  const permissions = computed(() =>
    getUserPermissions(currentUser.value, accountId.value)
  );

  // #2075 — valores de venda em R$: chave protegida, o crm_admin NÃO liga (espelho de Crm::ValorDeVenda.ve?).
  // Sem ela o servidor já manda o valor vazio; aqui a tela só some com o que não faria sentido (soma, filtro, ordem).
  const canSeeSalesValues = computed(
    () =>
      isUngatedSeat.value ||
      permissions.value.includes('administrator') ||
      permissions.value.includes(SALES_VALUE_VIEW_KEY)
  );

  const hasCrmPermission = key => {
    // sales_value_view não é chave do CRM: segue Crm::ValorDeVenda.ve? (ex.: escopos do token de integração).
    if (key === SALES_VALUE_VIEW_KEY) return canSeeSalesValues.value;
    if (isAdmin.value) return true;
    if (!customRoleId.value) return !PLAIN_AGENT_DENIED_KEYS.includes(key);
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
  // #1874 — arquivar tem chave própria; o agente sem função continua arquivando.
  const canDeleteCards = computed(() =>
    hasCrmPermission(CRM_DELETE_CARDS_PERMISSION)
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
  // Admin-equivalent CRM actions (e.g. minting integration tokens) require the
  // account administrator or the explicit crm_admin key (PLAIN_AGENT_DENIED_KEYS).
  const canAdminCrm = computed(() => hasCrmPermission(CRM_ADMIN_PERMISSION));
  // Excluir de vez (#2096): só o administrador da conta, nunca por função personalizada (regra do projeto:
  // apagar histórico de cliente sem volta não se delega). Espelho de Crm::CardPolicy#permanent_delete?.
  const canHardDelete = computed(() => isAdmin.value);

  // #722 — planilha da Lista é dado pessoal em lote: como canAdminCrm, o agente
  // sem função NÃO ganha por padrão (backend: crm_export em PLAIN_AGENT_DENIED_KEYS).
  const canExportCrm = computed(() => hasCrmPermission(CRM_EXPORT_PERMISSION));

  return {
    hasCrmPermission,
    canViewCrm,
    canManageCards,
    canMoveCards,
    canDeleteCards,
    canManagePipelines,
    canManageAi,
    canViewReports,
    canAdminCrm,
    canExportCrm,
    canHardDelete,
    canSeeSalesValues,
  };
}
