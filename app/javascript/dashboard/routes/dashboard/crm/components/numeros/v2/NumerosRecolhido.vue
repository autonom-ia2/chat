<script setup>
import { ref, useId } from 'vue';

// Seção recolhida de Números (#1871; visão "Equipe", #1992): o total fica no
// título; o resto abre ao tocar. Fechada por padrão, no celular e no computador.
defineProps({
  titulo: { type: String, required: true },
});

const aberto = ref(false);
const id = useId();
</script>

<template>
  <section
    class="flex flex-col rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
  >
    <h3 class="mb-0">
      <button
        type="button"
        :aria-expanded="aberto"
        :aria-controls="id"
        data-recolhido
        class="flex min-h-12 w-full items-center justify-between gap-3 rounded-xl px-4 text-start text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="aberto = !aberto"
      >
        {{ titulo }}
        <span
          class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform motion-reduce:transition-none"
          :class="{ 'rotate-180': aberto }"
          aria-hidden="true"
        />
      </button>
    </h3>
    <div
      v-show="aberto"
      :id="id"
      class="flex flex-col gap-3 border-t border-n-weak px-4 py-4"
    >
      <slot />
    </div>
  </section>
</template>
