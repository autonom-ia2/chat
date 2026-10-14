<script setup>
// #1447 — um agente de IA na lista: o rosto de robô, o nome, o selo que o
// separa de pessoa e administrador, e o que ele faz nesta caixa. `parado`:
// o agente não está atendendo agora.
defineProps({
  nome: { type: String, required: true },
  texto: { type: String, default: '' },
  parado: { type: Boolean, default: false },
});
</script>

<template>
  <div class="flex min-w-0 flex-1 items-center gap-3">
    <span
      class="grid size-9 shrink-0 place-items-center rounded-full bg-n-iris-3 text-n-iris-11"
      aria-hidden="true"
    >
      <span class="i-lucide-bot size-5" />
    </span>
    <div class="min-w-0 flex-1">
      <p class="mb-0 flex flex-wrap items-center gap-x-2 gap-y-1">
        <span class="truncate text-base font-semibold text-n-slate-12">
          {{ nome }}
        </span>
        <span
          data-selo-ia
          class="inline-flex items-center rounded-md bg-n-iris-3 px-1.5 py-0.5 text-xs font-medium text-n-iris-11"
        >
          {{ $t('CRM_CAIXAS.PESSOAS.SELO_IA') }}
        </span>
        <span
          v-if="parado"
          data-parado
          class="inline-flex items-center rounded-md bg-n-slate-3 px-1.5 py-0.5 text-xs font-medium text-n-slate-11"
        >
          {{ $t('CRM_CAIXAS.PESSOAS.PARADO') }}
        </span>
      </p>
      <p v-if="texto" class="mb-0 text-sm text-n-slate-11">{{ texto }}</p>
    </div>
  </div>
</template>
