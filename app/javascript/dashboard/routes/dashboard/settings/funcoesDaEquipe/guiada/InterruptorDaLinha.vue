<script setup>
import { useId } from 'vue';

// Uma linha com interruptor (#2308, especificação 9): o interruptor fica sempre à direita do rótulo, sem texto
// "Ligado" (o estado vai em aria-checked e na cor), com alvo de 44 px. Travado não tem interruptor: mostra o
// cadeado e o motivo, nunca só opacidade.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  nota: { type: String, default: '' },
  trava: { type: String, default: '' },
  ligado: { type: Boolean, default: false },
  mudou: { type: Boolean, default: false },
});

const emit = defineEmits(['alternar']);
const id = useId();
</script>

<template>
  <div
    class="flex items-center gap-4 py-3 ps-4 pe-2"
    :class="mudou ? 'border-s-4 border-n-blue-9 bg-n-blue-2 ps-3' : ''"
  >
    <div :id="`${id}-sobre`" class="flex flex-col flex-1 min-w-0 gap-0.5">
      <p
        class="flex flex-wrap items-center gap-2 m-0 font-medium text-n-slate-12"
      >
        {{ titulo }}
        <span
          v-if="mudou"
          class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
        >
          {{ $t('FUNCOES_EQUIPE.GUIADA.VOCE_MUDOU') }}
        </span>
      </p>
      <p v-if="texto" class="m-0 text-sm text-n-slate-11">{{ texto }}</p>
      <p
        v-if="nota"
        class="flex items-start gap-1.5 m-0 text-sm font-medium text-n-slate-12"
      >
        <span
          class="i-lucide-link size-4 mt-0.5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{ nota }}
      </p>
      <p
        v-if="trava"
        class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span class="i-lucide-lock size-4 mt-0.5 shrink-0" aria-hidden="true" />
        {{ trava }}
      </p>
    </div>
    <button
      v-if="!trava"
      type="button"
      role="switch"
      data-interruptor
      :aria-checked="ligado"
      :aria-label="titulo"
      :aria-describedby="`${id}-sobre`"
      class="grid place-items-center size-11 shrink-0 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('alternar')"
    >
      <span
        aria-hidden="true"
        class="relative block w-11 h-6 transition-colors rounded-full"
        :class="ligado ? 'bg-n-teal-9' : 'bg-n-slate-7'"
      >
        <span
          class="absolute top-0.5 start-0.5 size-5 rounded-full bg-white shadow transition-transform"
          :class="ligado ? 'ltr:translate-x-5 rtl:-translate-x-5' : ''"
        />
      </span>
    </button>
  </div>
</template>
