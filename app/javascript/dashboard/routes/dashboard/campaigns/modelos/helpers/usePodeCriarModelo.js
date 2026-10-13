import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';

// Criar, alterar, duplicar e apagar modelo: administrador ou função
// personalizada com campaign_manage. Os demais (agente, campaign_view) veem e
// usam em campanha.
export const PERMISSOES_PARA_CRIAR = ['administrator', 'campaign_manage'];

export function usePodeCriarModelo() {
  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  return computed(() =>
    getUserPermissions(usuario.value, contaId.value).some(permissao =>
      PERMISSOES_PARA_CRIAR.includes(permissao)
    )
  );
}
