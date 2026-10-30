import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { alcancaSemFuncao } from 'dashboard/routes/dashboard/settings/funcoesDaEquipe/semFuncao';

// Roles offered when adding or editing someone (#1931). Only an administrator makes an administrator, and a custom
// role out of the giver's reach stays visible but disabled, with the reason. The plain agent is open when adding
// someone; when editing someone who has a custom role, choosing it takes them out of the role, which follows the same
// rule as giving a role (#2317): with the "Sem função" keys out of the giver's reach, it is locked, with the reason.
// With custom roles off (a downgraded account), clearing a stale role stays open, as on the server.
export function useAgentRoleChoices({ currentCustomRoleId = null } = {}) {
  const { t } = useI18n();
  const customRoles = useMapGetter('customRole/getCustomRoles');
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
  const { giver, isAdmin, reachesRole } = usePeopleAccess();
  const isEnabled = flag =>
    Boolean(isFeatureEnabled.value?.(accountId.value, flag));
  const takeOutLocked = computed(
    () =>
      Boolean(currentCustomRoleId) &&
      isEnabled('custom_roles') &&
      !alcancaSemFuncao(giver.value, isEnabled)
  );

  const roles = computed(() => [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
      disabled: !isAdmin.value,
      hint: isAdmin.value ? '' : t('AGENT_MGMT.LOCK.ONLY_ADMIN_MAKES_ADMIN'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
      disabled: takeOutLocked.value,
      hint: takeOutLocked.value
        ? t('AGENT_MGMT.LOCK.ONLY_ADMIN_TAKES_OUT')
        : '',
    },
    ...customRoles.value.map(role => {
      const inReach = reachesRole(role);
      return {
        id: role.id,
        name: `custom_${role.id}`,
        label: role.name,
        disabled: !inReach,
        hint: inReach ? '' : t('AGENT_MGMT.LOCK.ABOVE'),
      };
    }),
  ]);

  const roleChoices = computed(() =>
    roles.value.map(role => ({
      value: role.id,
      label: role.label,
      disabled: Boolean(role.disabled),
      hint: role.hint || undefined,
    }))
  );

  return { roles, roleChoices };
}
