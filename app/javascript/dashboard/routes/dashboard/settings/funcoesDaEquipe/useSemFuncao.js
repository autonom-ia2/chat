import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { modulesWithKeys } from '../customRoles/permissionMatrix';
import { useTextos } from './guiada/useTextos';
import {
  capacidadesSemFuncao,
  diffEntre,
  premissasSemFuncao,
} from './semFuncao';

// semFuncao.js com as flags reais da conta (o mesmo getter que a lista usa para o plano) e os textos de cada item:
// LISTA para listas ("Vão passar a poder"), CURTO para o meio de uma frase ("passa a …"). Um id que o contrato ganhe
// antes do texto cai numa frase genérica com a área da chave, em vez de mostrar a chave crua.
export function useSemFuncao() {
  const { t, te, lista } = useTextos();
  const ligadaNaConta = useMapGetter('accounts/isFeatureEnabledonAccount');
  const accountId = useMapGetter('getCurrentAccountId');
  const estaLigada = flag =>
    Boolean(ligadaNaConta.value?.(accountId.value, flag));

  const nomeDaArea = key => t(`FUNCOES_EQUIPE.AREAS.${key}.NOME`);

  const texto = (item, forma) => {
    if (item.tipo === 'area') {
      const onde = item.jeito === 'PARTE' ? 'OUTRA' : `AREA.${item.jeito}`;
      return t(`FUNCOES_EQUIPE.SEM_FUNCAO.${onde}.${forma}`, {
        area: nomeDaArea(item.chave),
      });
    }
    const chave = `FUNCOES_EQUIPE.SEM_FUNCAO.${item.chave}.${forma}`;
    if (te(chave)) return t(chave);
    const area = modulesWithKeys(item.chaves || [])[0];
    return area
      ? t(`FUNCOES_EQUIPE.SEM_FUNCAO.OUTRA.${forma}`, {
          area: nomeDaArea(area.key),
        })
      : t(`FUNCOES_EQUIPE.SEM_FUNCAO.OUTRA_SEM_AREA.${forma}`);
  };
  const textoDa = item => texto(item, 'LISTA');
  const curtoDa = item => texto(item, 'CURTO');

  // "Mais detalhes": o que só vale nos canais ou nas colunas, montado pelas premissas do contrato.
  const notas = computed(() => [
    ...premissasSemFuncao(estaLigada).map(({ premissa, ids }) =>
      t(`FUNCOES_EQUIPE.SEM_FUNCAO.PREMISSA.${premissa}`, {
        coisas: lista(ids.map(id => curtoDa({ chave: id }))),
      })
    ),
    t('FUNCOES_EQUIPE.SEM_FUNCAO.NOTA_RESTO'),
  ]);

  return {
    capacidades: computed(() =>
      capacidadesSemFuncao(estaLigada).map(({ id, pode, chaves }) => ({
        chave: id,
        pode,
        chaves,
      }))
    ),
    diff: permissions => diffEntre(permissions || [], estaLigada),
    textoDa,
    curtoDa,
    notas,
  };
}
