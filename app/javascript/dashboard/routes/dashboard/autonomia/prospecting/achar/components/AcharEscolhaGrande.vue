<script setup>
// #2692 — um dos dois cartões grandes da folha "O que fazer com as {n}?"
// (molde CampaignJourney/AudienceSourceChoice.vue: min-h-44 rounded-3xl
// border-2). Rodada 3: empilhados também em 1440, com o ícone à esquerda e o
// título numa linha (cerca de 96 px).
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, required: true },
  icone: { type: String, required: true },
  tom: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  escolhido: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher']);
</script>

<template>
  <button
    type="button"
    role="radio"
    :aria-checked="escolhido"
    class="relative flex items-center w-full gap-4 p-4 transition border-2 border-solid shadow-sm min-h-24 rounded-2xl bg-n-solid-1 text-start hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
    :class="
      escolhido
        ? 'border-n-blue-9 ring-2 ring-n-blue-9'
        : 'border-n-slate-6 hover:border-n-slate-8'
    "
    data-escolha-grande
    @click="emit('escolher')"
  >
    <span
      class="grid shrink-0 size-12 place-items-center rounded-2xl"
      :class="tom"
      aria-hidden="true"
    >
      <span class="size-6" :class="icone" />
    </span>
    <span class="flex flex-col min-w-0 gap-1 pe-8">
      <strong class="text-base text-n-slate-12">{{ titulo }}</strong>
      <span class="text-sm text-n-slate-11">{{ texto }}</span>
    </span>
    <span
      v-if="escolhido"
      class="absolute grid text-white -translate-y-1/2 rounded-full top-1/2 end-4 size-6 place-items-center bg-n-blue-9"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-4" />
    </span>
  </button>
</template>
