import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// A flag por conta do menu novo (#1617), para as peças do fork que aparecem fora do menu (aba Números do CRM,
// linha "Gerenciado em Atribuição").
export function useMenuNovo() {
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const ligado = computed(() =>
    Boolean(
      isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.MENU_LATERAL_NOVO
      )
    )
  );
  return { ligado };
}
