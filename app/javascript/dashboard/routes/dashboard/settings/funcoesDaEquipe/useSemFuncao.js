import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { capacidadesSemFuncao, diffEntre } from './semFuncao';

// semFuncao.js com as flags reais da conta (o mesmo getter que a lista usa para o plano) e os textos de cada
// capacidade: LISTA para listas ("Vão passar a poder"), CURTO para o meio de uma frase ("passa a …").
export function useSemFuncao() {
  const { t } = useI18n();
  const ligadaNaConta = useMapGetter('accounts/isFeatureEnabledonAccount');
  const accountId = useMapGetter('getCurrentAccountId');
  const estaLigada = flag =>
    Boolean(ligadaNaConta.value?.(accountId.value, flag));

  return {
    capacidades: computed(() => capacidadesSemFuncao(estaLigada)),
    diff: permissions => diffEntre(permissions || [], estaLigada),
    textoDa: id => t(`FUNCOES_EQUIPE.SEM_FUNCAO.${id}.LISTA`),
    curtoDa: id => t(`FUNCOES_EQUIPE.SEM_FUNCAO.${id}.CURTO`),
  };
}
