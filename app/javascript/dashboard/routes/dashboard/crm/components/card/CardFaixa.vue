<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1423 — a faixa fixa logo abaixo do herói: como está o negócio (selo) e,
// enquanto ele está aberto, Ganhou e Perdeu sempre à vista,
// também no celular (numa linha própria, de ponta a ponta). Negócio que já
// terminou mostra Reabrir no Próximo passo, logo abaixo.
defineProps({
  status: { type: String, required: true },
  statusTom: { type: String, required: true },
  aberto: { type: Boolean, default: true },
  ganhar: { type: String, required: true },
  perder: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
});

defineEmits(['ganhou', 'perdeu']);
</script>

<template>
  <div
    data-card-faixa
    class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-2 border-b border-n-weak bg-n-solid-1 px-5 py-2 sm:px-8"
  >
    <span
      data-card-status
      class="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-sm font-medium"
      :class="statusTom"
    >
      <span class="size-1.5 rounded-full bg-current" aria-hidden="true" />
      {{ status }}
    </span>
    <span
      v-if="carregando"
      role="status"
      class="inline-flex items-center gap-1.5 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" aria-hidden="true" />
      {{ $t('CRM_CARD.CARREGANDO') }}
    </span>
    <span class="hidden flex-1 sm:block" aria-hidden="true" />
    <div
      v-if="podeGerenciar && !carregando && aberto"
      data-card-desfecho
      class="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto"
    >
      <Button
        data-card-ganhou
        :label="ganhar"
        icon="i-lucide-trophy"
        teal
        faded
        class="!min-h-11 justify-center"
        @click="$emit('ganhou')"
      />
      <Button
        data-card-perdeu
        :label="perder"
        icon="i-lucide-circle-x"
        ruby
        faded
        class="!min-h-11 justify-center"
        @click="$emit('perdeu')"
      />
    </div>
  </div>
</template>
