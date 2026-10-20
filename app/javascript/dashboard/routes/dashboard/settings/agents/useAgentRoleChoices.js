import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';

// Roles offered when adding or editing someone (#1931). Only an administrator makes an administrator, and a custom
// role out of the giver's reach stays visible but disabled, with the reason. The plain agent is always open.
export function useAgentRoleChoices() {
  const { t } = useI18n();
  const customRoles = useMapGetter('customRole/getCustomRoles');
  const { isAdmin, reachesRole } = usePeopleAccess();

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
