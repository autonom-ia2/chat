import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';

// #2597 — o espelho de Crm::ValorDeVenda.ve? para a chave que o catálogo manda
// com o valor protegido: o administrador e o agente sem função leem; a função
// personalizada lê só com a chave. É só para não oferecer o valor na tela:
// quem autoriza é o salvar (Receita) e a execução (Valores).
export const podeLerComChave = (permissao, { papel, funcaoId, permissoes }) =>
  papel === 'administrator' || !funcaoId || permissoes.includes(permissao);

export function usePodeLerValor() {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  const papel = useMapGetter('getCurrentRole');
  const funcaoId = useMapGetter('getCurrentCustomRoleId');

  return computed(() => {
    const permissoes = getUserPermissions(currentUser.value, accountId.value);
    return permissao =>
      podeLerComChave(permissao, {
        papel: papel.value,
        funcaoId: funcaoId.value,
        permissoes,
      });
  });
}
