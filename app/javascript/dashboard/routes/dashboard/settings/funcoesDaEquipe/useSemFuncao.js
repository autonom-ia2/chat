import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { modulesWithKeys } from '../customRoles/permissionMatrix';
import { useTextos } from './guiada/useTextos';
import {
  capacidadesSemFuncao,
  diffEntre,
  porPeso,
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

  // A área inteira vai com artigo e sem dois-pontos, na frase ("deixa de ver a Central de Ajuda") e na lista ("Ver os
  // Relatórios"), como a Perda de acesso (revisão do #2308, rodada 4).
  const areaNaFrase = key => t(`FUNCOES_EQUIPE.AREAS.${key}.COM_ARTIGO`);

  const texto = (item, forma) => {
    if (item.tipo === 'area') {
      if (item.jeito === 'PARTE')
        return t(`FUNCOES_EQUIPE.SEM_FUNCAO.OUTRA.${forma}`, {
          area: nomeDaArea(item.chave),
        });
      return t(`FUNCOES_EQUIPE.SEM_FUNCAO.AREA.${item.jeito}.${forma}`, {
        area: areaNaFrase(item.chave),
      });
    }
    const chave = `FUNCOES_EQUIPE.SEM_FUNCAO.${item.chave}.${forma}`;
    if (te(chave)) return t(chave);
    const area = modulesWithKeys(item.chaves || [])[0];
    return area
      ? t(`FUNCOES_EQUIPE.SEM_FUNCAO.ALGO.${forma}`, {
          area: nomeDaArea(area.key),
        })
      : t(`FUNCOES_EQUIPE.SEM_FUNCAO.OUTRA_SEM_AREA.${forma}`);
  };
  const textoDa = item => texto(item, 'LISTA');
  const curtoDa = item => texto(item, 'CURTO');
  const diff = permissions => diffEntre(permissions || [], estaLigada);

  // O efeito de ficar sem função numa frase, o mesmo na linha da pessoa e no rodapé da gaveta (revisão do #2308,
  // rodada 4): o primeiro ganho, a perda que mais pesa (porPeso) e, como "também", o ganho que só o administrador daria
  // (os R$). Os textos já vêm na forma curta; '' quando não há.
  const efeitoDe = permissions => {
    const { ganha, perde } = diff(permissions);
    const [ganho, ...outros] = ganha;
    const [perda] = porPeso(perde);
    return {
      ganho: ganho ? curtoDa(ganho) : '',
      perda: perda ? curtoDa(perda) : '',
      tambem: outros
        .filter(item => item.delegacao)
        .map(item =>
          t('FUNCOES_EQUIPE.EFEITO.TAMBEM', { ganho: curtoDa(item) })
        ),
    };
  };

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
    diff,
    efeitoDe,
    textoDa,
    curtoDa,
    notas,
  };
}
