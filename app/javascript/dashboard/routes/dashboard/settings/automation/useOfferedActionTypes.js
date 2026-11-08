import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { isCrmAutomationKey } from 'dashboard/composables/useCrmAutomationOptions';
import { AUTOMATION_ACTION_TYPES } from './constants';

// #2413 — the actions this panel offers. The form and the rehydration of a saved rule read the
// same list, so a step left out (Decider, CRM or SLA off) stays locked with its raw params.
export function useOfferedActionTypes() {
  const { isCloudFeatureEnabled } = useAccount();
  const globalConfig = useMapGetter('globalConfig/get');
  const isCrmEnabled = computed(
    () => globalConfig.value?.crmKanbanEnabled === true
  );
  const isAvailableKey = key => isCrmEnabled.value || !isCrmAutomationKey(key);

  const offeredActionTypes = computed(() =>
    AUTOMATION_ACTION_TYPES.filter(
      ({ key }) =>
        isAvailableKey(key) &&
        (key !== 'add_sla' || isCloudFeatureEnabled('sla'))
    )
  );

  return { isAvailableKey, offeredActionTypes };
}
