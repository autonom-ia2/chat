<script setup>
// #2692 — cartão de escolha de um toque (até 4 opções; mais que isso é
// ChoiceSelect). Molde automacoes/components/AutomacaoModelos.vue, sem as
// linhas em caixa alta: o cartão inteiro é o botão, min-h-16, o escolhido
// ganha anel azul e visto. Rodada 2: borda visível (border-n-slate-6) para o
// cartão ter cara de alvo de toque; `iniciais` põe o avatar (pessoas, molde
// crm/components/card/telas/TelaQuemCuida.vue).
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  escolhido: { type: Boolean, default: false },
  iniciais: { type: String, default: '' },
  // Selo curto ao lado do título (rodada 4: "Criado por você" nos modelos da pessoa).
  selo: { type: String, default: '' },
});
const emit = defineEmits(['escolher']);
</script>

<template>
  <button
    type="button"
    role="radio"
    :aria-checked="escolhido"
    class="relative flex w-full h-full gap-3 p-4 transition border-2 border-solid text-start min-h-16 rounded-2xl bg-n-solid-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
    :class="[
      escolhido
        ? 'border-n-blue-9 ring-2 ring-n-blue-9'
        : 'border-n-slate-6 hover:border-n-slate-8',
      texto ? 'items-start' : 'items-center',
    ]"
    data-escolha
    @click="emit('escolher')"
  >
    <span
      v-if="iniciais"
      class="grid text-sm font-semibold rounded-full shrink-0 size-10 place-items-center bg-n-blue-3 text-n-blue-11"
      aria-hidden="true"
    >
      {{ iniciais }}
    </span>
    <span class="flex flex-col min-w-0 gap-1 pe-8">
      <span class="flex flex-wrap items-center gap-2">
        <span class="text-base font-semibold text-n-slate-12">
          {{ titulo }}
        </span>
        <span
          v-if="selo"
          class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-violet-3 text-n-violet-11"
        >
          {{ selo }}
        </span>
      </span>
      <span v-if="texto" class="text-sm text-n-slate-11">{{ texto }}</span>
    </span>
    <span
      v-if="escolhido"
      :class="texto ? 'top-4' : 'top-1/2 -translate-y-1/2'"
      class="absolute grid text-white rounded-full end-4 size-6 place-items-center bg-n-blue-9"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-4" />
    </span>
  </button>
</template>
