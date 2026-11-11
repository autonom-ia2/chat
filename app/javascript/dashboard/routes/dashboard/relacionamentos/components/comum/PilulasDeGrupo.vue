<script setup>
import { nextTick, onMounted, ref, useTemplateRef, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

// #2894 — os grupos em pílulas, cada um com o seu número. A escolhida fica
// preenchida (aria-pressed, como a vitrine de ferramentas). No celular a fila
// rola para o lado; cada pílula tem 44 px de altura.
//   grupos: [{ id, nome, total }]    v-model: o id do grupo escolhido
const props = defineProps({
  grupos: { type: Array, required: true },
  modelValue: { type: String, default: '' },
  rotulo: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

// Quando a fila transborda, um degradê na borda onde há mais conteúdo mostra que
// ela continua (à direita; e à esquerda depois de rolar). Sem transbordo, nada.
const fila = useTemplateRef('fila');
const maisAEsquerda = ref(false);
const maisADireita = ref(false);
const FOLGA_PX = 2;
const medir = () => {
  const el = fila.value;
  if (!el) return;
  maisAEsquerda.value = el.scrollLeft > FOLGA_PX;
  maisADireita.value =
    el.scrollLeft + el.clientWidth < el.scrollWidth - FOLGA_PX;
};
onMounted(medir);
useResizeObserver(fila, medir);
watch(
  () => props.grupos,
  () => nextTick(medir),
  { deep: true }
);
</script>

<template>
  <nav
    class="relative min-w-0"
    :aria-label="rotulo || t('RELACIONAMENTOS.COMUM.GRUPOS')"
  >
    <ul
      ref="fila"
      class="flex gap-2 p-0 pb-1 m-0 overflow-x-auto list-none snap-x scroll-px-12"
      @scroll.passive="medir"
    >
      <li v-for="grupo in grupos" :key="grupo.id" class="snap-start">
        <button
          type="button"
          :data-grupo="grupo.id"
          :aria-pressed="modelValue === grupo.id ? 'true' : 'false'"
          class="inline-flex items-center gap-2 px-4 text-sm font-medium rounded-full whitespace-nowrap min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :class="
            modelValue === grupo.id
              ? 'bg-n-blue-11 text-white ring-n-blue-11 dark:text-n-slate-1'
              : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:bg-n-alpha-1'
          "
          @click="emit('update:modelValue', grupo.id)"
        >
          {{ grupo.nome }}
          <span
            v-if="grupo.total !== undefined && grupo.total !== null"
            class="tabular-nums opacity-75"
          >
            {{ grupo.total }}
          </span>
        </button>
      </li>
    </ul>
    <span
      v-if="maisAEsquerda"
      data-degrade="esquerda"
      aria-hidden="true"
      class="absolute inset-y-0 start-0 w-10 pointer-events-none bg-gradient-to-r from-n-surface-1 to-transparent rtl:bg-gradient-to-l"
    />
    <span
      v-if="maisADireita"
      data-degrade="direita"
      aria-hidden="true"
      class="absolute inset-y-0 end-0 w-10 pointer-events-none bg-gradient-to-l from-n-surface-1 to-transparent rtl:bg-gradient-to-r"
    />
  </nav>
</template>
