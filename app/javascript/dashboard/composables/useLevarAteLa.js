import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import {
  isGuideRoute,
  guideRouteFeature,
} from 'dashboard/helper/guideRouteRegistry';
import { guideRouteParams } from 'dashboard/helper/guideNavigation';
import { useGuideHighlight } from 'dashboard/store/modules/guideHighlight';

// Espera o fechamento de painéis que cobririam o elemento antes de acendê-lo.
export const ESPERA_DO_DESTAQUE_MS = 320;

// "Me leve até lá": leva a pessoa até uma tela da conta dela e acende o elemento certo. É o mesmo
// caminho do Guia (#590): a rota precisa estar na lista do Guia, o recurso ligado na conta e o
// endereço resolver no roteador; senão não há botão. O guard do roteador ainda confere a permissão.
export function useLevarAteLa() {
  const router = useRouter();
  const { accountScopedRoute } = useAccount();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const destaque = useGuideHighlight();

  const destino = (rota, params) => {
    if (!rota || !isGuideRoute(rota)) return null;
    const recurso = guideRouteFeature(rota);
    if (recurso && !isFeatureEnabledonAccount.value(accountId.value, recurso)) {
      return null;
    }
    try {
      const alvo = accountScopedRoute(rota, guideRouteParams(params));
      return router.resolve(alvo)?.matched?.length ? alvo : null;
    } catch {
      return null;
    }
  };

  const acender = ancora => {
    if (!ancora) return;
    setTimeout(() => destaque.show(ancora), ESPERA_DO_DESTAQUE_MS);
  };

  const levar = ({ rota, destaque: ancora, params } = {}) => {
    const alvo = destino(rota, params);
    if (!alvo) return false;
    router.push(alvo);
    acender(ancora);
    return true;
  };

  return { destino, levar, acender };
}
