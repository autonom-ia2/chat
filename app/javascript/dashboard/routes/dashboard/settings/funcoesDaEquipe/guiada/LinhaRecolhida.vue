<script setup>
import { ref, useId } from 'vue';

// A recolhida (#2308, especificação 9): alpha-1 + anel, quadrado de 40 px, título, estado e "Abrir". O botão diz
// se está aberta (aria-expanded) e aponta para o que mostra.
defineProps({
  icone: { type: String, required: true },
  titulo: { type: String, required: true },
  estado: { type: String, default: '' },
});

const aberta = ref(false);
const id = useId();
</script>

<template>
  <section class="rounded-2xl ring-1 ring-n-weak bg-n-alpha-1">
    <button
      type="button"
      data-recolhida
      :aria-expanded="aberta"
      :aria-controls="id"
      class="flex items-center w-full gap-3 px-4 py-3 text-start min-h-11 rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="aberta = !aberta"
    >
      <span
        class="grid place-items-center size-10 shrink-0 rounded-xl bg-n-alpha-2 text-n-slate-11"
      >
        <span class="size-5" :class="icone" aria-hidden="true" />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="font-semibold text-n-slate-12">{{ titulo }}</span>
        <span v-if="estado" class="text-sm text-n-slate-11">{{ estado }}</span>
      </span>
      <span class="inline-flex items-center gap-1 text-sm text-n-slate-11">
        {{
          aberta
            ? $t('FUNCOES_EQUIPE.GUIADA.FECHAR')
            : $t('FUNCOES_EQUIPE.GUIADA.ABRIR')
        }}
        <span
          class="i-lucide-chevron-down size-4 transition-transform"
          :class="aberta ? 'rotate-180' : ''"
          aria-hidden="true"
        />
      </span>
    </button>
    <div v-if="aberta" :id="id" class="border-t border-n-weak">
      <slot />
    </div>
  </section>
</template>
