<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import RessalvasDaConferencia from '../comum/RessalvasDaConferencia.vue';

// #2226 v2 (§2.10) — vendas perdidas por causa que a empresa pode corrigir (fora preço e quem só
// pesquisou): o número grande, por quê (com as conversas de exemplo) e onde travam todas as procuras.
const props = defineProps({
  painel: { type: Object, required: true },
});

const emit = defineEmits(['detalhe']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.PERDAS';
const LIMITE_DE_MOTIVOS = 8;
// Só os 2 motivos que mais pesam ficam em vermelho forte; o resto, em tom neutro.
const MOTIVOS_EM_ALERTA = 2;

const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);
const perdas = computed(() => props.painel.perdas || {});
const porMotivo = computed(() =>
  (perdas.value.por_motivo || []).map((item, indice) => ({
    ...item,
    valor: item.procuras,
    pct: null,
    cor: indice < MOTIVOS_EM_ALERTA ? 'alerta' : 'neutro',
  }))
);
const travas = computed(() =>
  (props.painel.motivos?.ranking || []).map(item => ({
    ...item,
    valor: item.procuras,
    exemplos: [],
  }))
);
</script>

<template>
  <section
    id="perdas"
    aria-labelledby="perdas-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="perdas-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
      <span
        data-total-perdas
        class="text-4xl font-bold leading-none tabular-nums text-n-ruby-11"
      >
        {{ fmt.n(perdas.total) }}
      </span>
      <span class="text-sm tabular-nums text-n-slate-12">
        {{
          fmt.t(`${NS}.DA_COMPRA`, {
            pct: fmt.pct(perdas.pct_da_compra),
            m: fmt.n(painel.funil?.base),
            compra: minusculo(painel.meta.nomes.compra),
          })
        }}
      </span>
      <button
        v-if="perdas.total"
        type="button"
        data-ver-perdas
        class="text-sm font-semibold rounded-md min-h-11 text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('detalhe', { perda: '1' })"
      >
        {{ fmt.t(`${NS}.VER_NA_TABELA`, { n: fmt.n(perdas.total) }) }}
      </button>
    </div>
    <RessalvasDaConferencia :painel="painel" parte="perdas" />
    <div class="grid items-start gap-4 xl:grid-cols-2">
      <CartaoDoPainel
        data-por-motivo
        :titulo="fmt.t(`${NS}.POR_QUE`)"
        :descricao="fmt.t(`${NS}.POR_QUE_DESCRICAO`)"
        :unidade="fmt.t(`${NS}.UNIDADE_POR_QUE`)"
      >
        <RankingDeBarras
          :itens="porMotivo"
          cor="alerta"
          :rotulo="fmt.t(`${NS}.POR_QUE`)"
        />
      </CartaoDoPainel>
      <CartaoDoPainel
        :titulo="fmt.t(`${NS}.ONDE_TRAVAM`)"
        :descricao="
          fmt.t(`${NS}.ONDE_TRAVAM_DESCRICAO`, {
            n: fmt.n(painel.motivos?.com_motivo),
            m: fmt.n(painel.motivos?.base),
            compra: minusculo(painel.meta.nomes.compra),
          })
        "
        :unidade="
          fmt.t(`${NS}.BASE_TRAVAS`, { n: fmt.n(painel.motivos?.com_motivo) })
        "
      >
        <RankingDeBarras
          :itens="travas"
          cor="neutro"
          :limite="LIMITE_DE_MOTIVOS"
          :rotulo="fmt.t(`${NS}.ONDE_TRAVAM`)"
        />
      </CartaoDoPainel>
    </div>
  </section>
</template>
