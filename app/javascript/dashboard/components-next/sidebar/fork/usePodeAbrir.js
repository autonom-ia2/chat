import { useRouter } from 'vue-router';
import { usePolicy } from 'dashboard/composables/usePolicy';

// A mesma checagem de rota do menu (provider.js isAllowed) para quem está fora do <Sidebar>: permissão, flag e
// tipo de instalação da rota de destino.
export function usePodeAbrir() {
  const router = useRouter();
  const { shouldShow } = usePolicy();

  const podeAbrir = to => {
    if (!to) return false;
    const rota = router.resolve(to);
    return shouldShow(
      rota.meta?.featureFlag || '',
      rota.meta?.permissions || [],
      rota.meta?.installationTypes || []
    );
  };

  return { podeAbrir };
}
