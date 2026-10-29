<script setup>
import { computed, useId } from 'vue';

// Uma linha com interruptor (#2308, especificação 9): o interruptor fica sempre à direita do rótulo, sem texto
// "Ligado" (o estado vai em aria-checked e na cor), com alvo de 44 px. Travado desligado não tem interruptor: mostra
// o cadeado e o motivo, nunca só opacidade. Travado ligado (vem com "Cuida de tudo", o último alcance) mostra o
// interruptor ligado com aria-disabled e o motivo embaixo: o toque não faz nada, mas a linha diz por quê. O nome do
// interruptor é o título; a descrição é só o resto (texto, nota, motivo), para o leitor não ler o título duas vezes.
const props = defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  nota: { type: String, default: '' },
  trava: { type: String, default: '' },
  // O cadeado diz "você não pode dar isto"; uma regra que não é de permissão (o último alcance) usa o info.
  iconeDaTrava: { type: String, default: 'i-lucide-lock' },
  ligado: { type: Boolean, default: false },
  mudou: { type: Boolean, default: false },
});

const emit = defineEmits(['alternar']);
const id = useId();

const preso = computed(() => Boolean(props.trava) && props.ligado);
const descricao = computed(() =>
  ['texto', 'nota', 'trava']
    .filter(parte => props[parte])
    .map(parte => `${id}-${parte}`)
    .join(' ')
);
const alternar = () => {
  if (!preso.value) emit('alternar');
};
</script>

<template>
  <div
    class="flex items-center gap-4 py-3 ps-4 pe-2"
    :class="mudou ? 'border-s-4 border-n-blue-9 bg-n-blue-2 ps-3' : ''"
  >
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
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
      <p v-if="texto" :id="`${id}-texto`" class="m-0 text-sm text-n-slate-11">
        {{ texto }}
      </p>
      <p
        v-if="nota"
        :id="`${id}-nota`"
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
        :id="`${id}-trava`"
        class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span
          class="size-4 mt-0.5 shrink-0"
          :class="iconeDaTrava"
          aria-hidden="true"
        />
        {{ trava }}
      </p>
    </div>
    <button
      v-if="!trava || preso"
      type="button"
      role="switch"
      data-interruptor
      :aria-checked="ligado"
      :aria-disabled="preso || undefined"
      :aria-label="titulo"
      :aria-describedby="descricao || undefined"
      class="grid p-0 place-items-center size-11 shrink-0 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="{ 'cursor-not-allowed': preso }"
      @click="alternar"
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
