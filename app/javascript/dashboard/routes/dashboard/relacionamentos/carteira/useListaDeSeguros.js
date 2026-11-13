// #2897 — o estado da aba Seguros: a lista (o mesmo `useLista` da lista de
// pessoas, com os grupos, a ordem e os filtros de seguros) e os textos que
// dependem da consulta. A página só liga as peças.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ABA_SEGUROS,
  FILTROS_DE_SEGUROS_VAZIOS,
  ORDENS_DE_SEGUROS,
  contarFiltrosDeSeguros,
} from '../fonte/carteiraFonte';
import {
  GRUPOS_DE_SEGUROS,
  GRUPO_PADRAO_DE_SEGUROS,
  GRUPO_VENCIDO,
} from '../fonte/gruposDeSeguros';
import { useLista } from '../lista/useLista';

export const useListaDeSeguros = fonte => {
  const { t } = useI18n();
  const daLista = (chave, valores) =>
    t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores);

  const lista = useLista({
    fonte,
    aba: ref(ABA_SEGUROS),
    grupoPadrao: () => GRUPO_PADRAO_DE_SEGUROS,
    ordemPadrao: ORDENS_DE_SEGUROS.VENCE_PRIMEIRO,
    filtrosVazios: FILTROS_DE_SEGUROS_VAZIOS,
    contar: contarFiltrosDeSeguros,
  });

  const grupos = computed(() =>
    GRUPOS_DE_SEGUROS.map(({ id, nome }) => ({
      id,
      nome: t(nome),
      total: lista.contagens.value[id],
    }))
  );
  const explicacao = computed(() => {
    const atual = GRUPOS_DE_SEGUROS.find(g => g.id === lista.grupo.value);
    return atual?.explicacao ? t(atual.explicacao) : '';
  });

  // Quantos seguros da carteira estão vencidos, para a frase do topo. É a
  // contagem do grupo Vencido que a barra de grupos já carrega (não há pedido
  // novo). Ela segue a busca e os filtros; a frase do topo fala da carteira
  // inteira, então só vale a contagem lida sem busca e sem filtro.
  // `contagensLidas` liga na primeira resposta: a frase do topo espera por
  // ela, para não dizer uma coisa e trocar logo depois.
  const vencidos = ref(0);
  const contagensLidas = ref(false);
  watch(lista.contagens, contagens => {
    contagensLidas.value = true;
    if (lista.busca.value || lista.filtrosAtivos.value) return;
    vencidos.value = contagens[GRUPO_VENCIDO] ?? 0;
  });

  // A lista sem nenhum seguro: a frase (e a saída, quando há) depende do que a
  // pessoa pediu. A tela e o aviso falado nascem da mesma conta.
  const semResultado = computed(() => {
    if (lista.itens.value.length) return null;
    if (lista.busca.value) {
      return {
        frase: daLista('BUSCA_SEM_RESULTADO', { busca: lista.busca.value }),
        botao: daLista('LIMPAR_BUSCA'),
        acao: () => lista.mudarBusca(''),
      };
    }
    if (lista.filtrosAtivos.value) {
      return {
        frase: daLista('FILTROS.SEM_RESULTADO'),
        botao: daLista('FILTROS.LIMPAR_FILTROS'),
        acao: lista.limparFiltros,
      };
    }
    return { frase: daLista('GRUPO_VAZIO'), botao: '', acao: null };
  });

  return {
    lista,
    grupos,
    explicacao,
    vencidos,
    // O topo (a frase e os grupos) tem o que mostrar: o resumo e as contagens.
    topoPronto: computed(
      () => Boolean(lista.resumo.value) && contagensLidas.value
    ),
    semResultado,
    semSeguros: computed(() => lista.resumo.value?.total === 0),
    avisoDaLista: computed(() =>
      !lista.erro.value && !lista.carregando.value && semResultado.value
        ? semResultado.value.frase
        : ''
    ),
  };
};
