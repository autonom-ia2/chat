import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';

// Custom-role seats edit a module only with its `<module>_manage` key (#452); a `_view` seat gets a
// read-only page. Every other seat keeps its role-based access, already enforced by routes and API.
export function useCanManage(manageKey) {
  const currentUser = useMapGetter('getCurrentUser');
  const customRoleId = useMapGetter('getCurrentCustomRoleId');
  const accountId = useMapGetter('getCurrentAccountId');

  return computed(
    () =>
      !customRoleId.value ||
      getUserPermissions(currentUser.value, accountId.value).includes(manageKey)
  );
}
