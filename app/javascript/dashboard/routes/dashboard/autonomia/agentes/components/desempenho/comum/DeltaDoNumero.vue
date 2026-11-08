<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { delta } from '../../../utils/desempenhoContrato';

// #2226 v2 — a comparação com o período anterior de mesmo tamanho: seta, quanto mudou e a cor pelo
// que é bom para este número (kpi.melhor). Taxa compara em pontos ("3 pontos a menos"), nunca pela
// contagem. Sem período anterior, não aparece.
const props = defineProps({
  kpi: { type: Object, required: true },
  dias: { type: Number, default: 0 },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.DELTA';

const COR_DO_SENTIDO = {
  favoravel: 'text-n-teal-11',
  desfavoravel: 'text-n-ruby-11',
  neutro: 'text-n-slate-11',
};

const mudanca = computed(() => delta(props.kpi));

const quanto = computed(() => {
  const valor = Math.abs(mudanca.value.diferenca);
  if (mudanca.value.unidade === 'pontos') return fmt.pontos(valor);
  if (props.kpi.formato === 'pct') return fmt.pontos(valor);
  if (props.kpi.formato === 'segundos') return fmt.segundos(valor);
  if (props.kpi.formato === 'dinheiro') return fmt.dinheiro(valor);
  return fmt.n(valor);
});

const texto = computed(() => {
  const { diferenca } = mudanca.value;
  const quando = props.dias
    ? fmt.t(`${NS}.DIAS_ANTES`, { dias: props.dias })
    : fmt.t(`${NS}.ANTES`);
  if (!diferenca) return fmt.t(`${NS}.IGUAL`, { quando });
  return fmt.t(diferenca > 0 ? `${NS}.MAIS` : `${NS}.MENOS`, {
    valor: quanto.value,
    quando,
  });
});

const seta = computed(() => {
  const { diferenca } = mudanca.value;
  if (!diferenca) return 'i-lucide-equal';
  return diferenca > 0 ? 'i-lucide-arrow-up' : 'i-lucide-arrow-down';
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <p
    v-if="mudanca"
    data-delta
    :data-sentido="mudanca.sentido"
    :data-unidade="mudanca.unidade"
    class="flex items-start gap-1 m-0 text-xs font-medium tabular-nums"
    :class="COR_DO_SENTIDO[mudanca.sentido] || COR_DO_SENTIDO.neutro"
  >
    <span class="size-3.5 mt-px shrink-0" :class="seta" aria-hidden="true" />
    {{ texto }}
  </p>
</template>
