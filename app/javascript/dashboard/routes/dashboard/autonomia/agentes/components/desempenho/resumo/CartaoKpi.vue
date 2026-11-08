<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { corDe, serieDoKpi } from '../../../utils/desempenhoCores';
import {
  KPIS,
  pct as pctDe,
  poucosCasos,
} from '../../../utils/desempenhoContrato';
import DeltaDoNumero from '../comum/DeltaDoNumero.vue';

// #2226 v2 (§2.1) — um número do topo: barra de cor da série à esquerda, rótulo, número grande, uma
// linha que diz o que ele conta e a comparação com o período anterior. O nome de "compra" e de
// "fechou" vem dos dados (meta.nomes), nunca do código; o nome da IA também (`agente`).
const props = defineProps({
  kpi: { type: Object, required: true },
  nomes: { type: Object, required: true },
  agente: { type: String, default: '' },
  dias: { type: Number, default: 0 },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.KPI';
const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);

const base = computed(() => props.kpi.base || { n: 0, m: 0 });
const pctDaBase = computed(() => fmt.pct(pctDe(base.value.n, base.value.m)));
const chave = computed(() => String(props.kpi.id || '').toUpperCase());
const conhecido = computed(() => KPIS.includes(props.kpi.id));

const rotulo = computed(() => {
  if (props.kpi.id === 'compra') return props.nomes.compra;
  if (props.kpi.id === 'fecharam') return props.nomes.fechou;
  if (!conhecido.value) return fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEM_NOME');
  return fmt.t(`${NS}.${chave.value}.ROTULO`, { nome: props.agente });
});

// Dúvidas resolvidas mostram a taxa grande; o resto, o valor no formato do contrato.
const numero = computed(() =>
  props.kpi.id === 'duvidas_resolvidas' && props.kpi.base
    ? pctDaBase.value
    : fmt.valorDoKpi(props.kpi)
);

// "Pedido pago: 10 · Retirou na loja: 5" (nome do dado e número, sem depender de plural).
const composicao = computed(() =>
  (props.kpi.composicao || [])
    .map(parte => `${parte.nome}: ${fmt.n(parte.valor)}`)
    .join(' · ')
);

const explicacao = computed(() => {
  const valores = {
    pct: pctDaBase.value,
    n: fmt.n(base.value.n),
    m: fmt.n(base.value.m),
    explicacao: props.nomes.compra_explicacao || '',
    compra: minusculo(props.nomes.compra),
    p90: fmt.segundos(props.kpi.extra?.p90),
    nome: props.agente,
  };
  return conhecido.value ? fmt.t(`${NS}.${chave.value}.EXPLICA`, valores) : '';
});

const serie = computed(() => serieDoKpi(props.kpi));

const comPoucosCasos = computed(
  () => Boolean(props.kpi.base) && poucosCasos(base.value.m)
);
</script>

<template>
  <article
    data-kpi
    :data-id="kpi.id"
    class="relative flex flex-col gap-1.5 p-4 overflow-hidden shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-n-weak dark:shadow-none"
  >
    <span
      class="absolute inset-y-0 w-1 start-0"
      :class="corDe(serie).fundo"
      aria-hidden="true"
    />
    <h3 class="m-0 text-xs font-semibold text-n-slate-11 line-clamp-2">
      {{ rotulo }}
    </h3>
    <p
      data-numero
      class="m-0 text-3xl font-bold leading-none tabular-nums text-n-slate-12"
    >
      {{ numero }}
    </p>
    <p data-explica class="m-0 text-xs text-n-slate-11 tabular-nums">
      {{ explicacao }}
    </p>
    <p
      v-if="composicao"
      data-composicao
      class="m-0 text-xs text-n-slate-11 tabular-nums"
    >
      {{ composicao }}
    </p>
    <p
      v-if="comPoucosCasos"
      data-poucos-casos
      class="m-0 text-xs font-semibold text-n-amber-11"
    >
      {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.POUCOS_CASOS') }}
    </p>
    <DeltaDoNumero class="mt-auto" :kpi="kpi" :dias="dias" />
  </article>
</template>
