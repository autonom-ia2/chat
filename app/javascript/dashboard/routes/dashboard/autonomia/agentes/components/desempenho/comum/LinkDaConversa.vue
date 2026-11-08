<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { hrefDaConversa } from '../../../utils/desempenhoContrato';

// #2226 v2 — a prova de um número: "Conversa #312 · 30/06 10:43", que abre a conversa em outra aba
// (o painel continua onde estava). O número é o que a pessoa vê na caixa de entrada. O resumo vai no
// title e, com `comResumo`, numa linha embaixo.
const props = defineProps({
  prova: { type: Object, required: true },
  comResumo: { type: Boolean, default: false },
});

const fmt = useFormatoDoPainel();
const router = useRouter();
const NS = 'AGENTS.DESEMPENHO2.A.COMUM';

const href = computed(() => hrefDaConversa(router, props.prova.conversa));
const rotulo = computed(() => {
  const numero = fmt.t(`${NS}.CONVERSA`, { numero: props.prova.conversa });
  return props.prova.quando
    ? `${numero} · ${fmt.dataHora(props.prova.quando)}`
    : numero;
});
</script>

<template>
  <span data-link-conversa class="inline-flex flex-col min-w-0 gap-0.5">
    <a
      :href="href"
      target="_blank"
      rel="noopener noreferrer"
      :title="prova.resumo || undefined"
      class="relative inline-flex items-center gap-1.5 text-sm font-medium min-h-11 tabular-nums text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 rounded-md"
    >
      <span
        class="i-lucide-message-circle size-4 shrink-0"
        aria-hidden="true"
      />
      {{ rotulo }}
      <span class="sr-only">{{ fmt.t(`${NS}.NOVA_ABA`) }}</span>
    </a>
    <span
      v-if="comResumo && prova.resumo"
      data-resumo
      class="-mt-2 text-xs text-n-slate-11"
    >
      {{ prova.resumo }}
    </span>
  </span>
</template>
