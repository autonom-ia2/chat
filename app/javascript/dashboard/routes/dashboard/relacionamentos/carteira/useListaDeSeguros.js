// #2897 — o estado da aba Seguros: a lista (o mesmo `useLista` do bloco A, com
// os grupos, a ordem e os filtros de seguros), quem está marcado e os textos
// que dependem da consulta. A página só liga as peças.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ABA_SEGUROS,
  FILTROS_DE_SEGUROS_VAZIOS,
  ORDENS_DE_SEGUROS,
  contarFiltrosDeSeguros,
} from '../fonte/carteiraFonte';
import {
  GRUPO_PADRAO_DE_SEGUROS,
  gruposDeSeguros,
} from '../fonte/gruposDeSeguros';
import { useLista } from '../lista/useLista';
import { useMarcados } from '../lista/useMarcados';
import { pessoasDosSeguros } from './pessoasDosSeguros';

export const useListaDeSeguros = fonte => {
  const { t } = useI18n();
  const daLista = (chave, valores) =>
    t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores);

  const marcados = useMarcados();
  const lista = useLista({
    fonte,
    aba: ref(ABA_SEGUROS),
    aoMudarConsulta: marcados.limpar,
    grupoPadrao: () => GRUPO_PADRAO_DE_SEGUROS,
    ordemPadrao: ORDENS_DE_SEGUROS.VENCE_PRIMEIRO,
    filtrosVazios: FILTROS_DE_SEGUROS_VAZIOS,
    contar: contarFiltrosDeSeguros,
  });

  const gruposDaConta = computed(() =>
    gruposDeSeguros({ aggerLigado: lista.resumo.value?.aggerLigado })
  );
  const grupos = computed(() =>
    gruposDaConta.value.map(({ id, nome }) => ({
      id,
      nome: t(nome),
      total: lista.contagens.value[id],
    }))
  );
  const explicacao = computed(() => {
    const atual = gruposDaConta.value.find(g => g.id === lista.grupo.value);
    return atual?.explicacao ? t(atual.explicacao) : '';
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
    marcados,
    grupos,
    explicacao,
    semResultado,
    // A mensagem vai por pessoa: quem tem dois seguros marcados entra uma vez.
    pessoasMarcadas: computed(() => pessoasDosSeguros(marcados.pessoas.value)),
    semSeguros: computed(() => lista.resumo.value?.total === 0),
    faltamMarcar: computed(
      () =>
        marcados.quantos.value > 0 && marcados.quantos.value < lista.total.value
    ),
    avisoDaLista: computed(() =>
      !lista.erro.value && !lista.carregando.value && semResultado.value
        ? semResultado.value.frase
        : ''
    ),
  };
};
