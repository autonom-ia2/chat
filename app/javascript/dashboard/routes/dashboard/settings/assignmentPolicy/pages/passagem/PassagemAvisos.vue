<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #1385 — o que impede a passagem de acontecer de verdade, num aviso só, com uma ação. A página só o mostra quando
// falta algo. Com a assistente desligada, a ação leva ao quadro do CRM (o funil se edita de lá; a rota não abre um
// funil direto); sem caixa só, leva direto para Caixas no CRM.
const props = defineProps({
  iaLigada: { type: Boolean, default: true },
  semCaixa: { type: Boolean, default: false },
});

const A = 'CRM_KANBAN.PASSAGEM.AVISOS';
const faltas = computed(() => [
  ...(props.iaLigada ? [] : [`${A}.FALTA_IA`]),
  ...(props.semCaixa ? [`${A}.FALTA_CAIXA`] : []),
]);
const acao = computed(() =>
  props.iaLigada
    ? {
        rotulo: `${A}.BOTAO_CAIXA`,
        icone: 'i-lucide-inbox',
        rota: 'crm_caixas',
      }
    : {
        rotulo: `${A}.BOTAO_FUNIL`,
        icone: 'i-lucide-kanban',
        rota: 'crm_kanban_index',
      }
);
</script>

<template>
  <div
    data-aviso="falta"
    class="flex flex-col items-start gap-3 rounded-2xl border border-dashed border-n-amber-8 bg-n-amber-2 p-4 sm:flex-row sm:items-center"
  >
    <span class="flex min-w-0 flex-1 items-start gap-3">
      <span
        class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span class="flex min-w-0 flex-col gap-1">
        <strong class="text-[0.9375rem] font-semibold text-n-slate-12">{{
          $t(`${A}.TITULO`)
        }}</strong>
        <ul
          class="m-0 flex list-disc flex-col gap-0.5 ps-5 text-[0.9375rem] text-n-slate-12"
        >
          <li v-for="falta in faltas" :key="falta">{{ $t(falta) }}</li>
        </ul>
      </span>
    </span>
    <Button
      :label="$t(acao.rotulo)"
      :icon="acao.icone"
      amber
      class="!min-h-11 shrink-0"
      @click="$router.push({ name: acao.rota })"
    />
  </div>
</template>
