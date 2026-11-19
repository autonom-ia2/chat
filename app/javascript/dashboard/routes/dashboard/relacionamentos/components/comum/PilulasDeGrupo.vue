<script setup>
import { computed, nextTick, onMounted, ref, useTemplateRef, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

// #2894 — os grupos em pílulas, cada um com o seu número. A escolhida fica
// preenchida (aria-pressed, como a vitrine de ferramentas). No celular a fila
// rola para o lado (com degradê quando continua); de `md` em diante ela quebra
// em linhas, sem rolagem; cada pílula tem 44 px de altura.
//   grupos: [{ id, nome, total }]    v-model: o id do grupo escolhido
// #3057 — redesenho: pílulas menores com o número em tom suave e a escolhida
// em tinta escura. No celular, uma linha que rola de lado (o degradê diz que
// continua); de `md` em diante as pílulas voltam a quebrar em linhas, todas à
// vista. A área de toque continua com 44 px: o botão é
// mais alto que a pílula que se vê. Com `semVazios` (as listas de
// Relacionamentos), grupo com 0 não aparece, para o leigo não escolher um
// grupo vazio; o primeiro ("Todos") e o escolhido ficam sempre, e o escolhido
// com 0 aparece apagado.
const props = defineProps({
  grupos: { type: Array, required: true },
  modelValue: { type: String, default: '' },
  rotulo: { type: String, default: '' },
  semVazios: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const vazio = grupo => grupo.total === 0;
const visiveis = computed(() =>
  props.grupos.filter(
    (grupo, indice) =>
      !props.semVazios ||
      indice === 0 ||
      grupo.id === props.modelValue ||
      !vazio(grupo)
  )
);
const temNumero = grupo => grupo.total !== undefined && grupo.total !== null;
const tomDaPilula = grupo => {
  if (props.modelValue === grupo.id) {
    return 'bg-n-slate-12 text-n-slate-1 ring-n-slate-12';
  }
  return vazio(grupo)
    ? 'bg-transparent text-n-slate-10 ring-n-weak group-hover:bg-n-alpha-1'
    : 'bg-n-solid-1 text-n-slate-12 ring-n-weak group-hover:bg-n-alpha-1 group-hover:ring-n-slate-6';
};

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
      data-relacionamentos="grupos"
      class="flex gap-1.5 p-0 m-0 overflow-x-auto list-none snap-x scroll-px-12 [scrollbar-width:none] md:flex-wrap md:overflow-visible"
      @scroll.passive="medir"
    >
      <li v-for="grupo in visiveis" :key="grupo.id" class="snap-start shrink-0">
        <button
          type="button"
          :data-grupo="grupo.id"
          :data-vazio="vazio(grupo) ? '' : undefined"
          :aria-pressed="modelValue === grupo.id ? 'true' : 'false'"
          class="flex items-center p-0 bg-transparent border-0 outline-none group min-h-11"
          @click="emit('update:modelValue', grupo.id)"
        >
          <span
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm font-medium rounded-full whitespace-nowrap ring-1 ring-inset transition-colors group-focus-visible:outline group-focus-visible:outline-2 group-focus-visible:outline-offset-1 group-focus-visible:outline-n-brand"
            :class="tomDaPilula(grupo)"
          >
            {{ grupo.nome }}
            <span
              v-if="temNumero(grupo)"
              class="text-xs tabular-nums"
              :class="
                modelValue === grupo.id ? 'opacity-70' : 'text-n-slate-10'
              "
            >
              {{ grupo.total }}
            </span>
          </span>
        </button>
      </li>
    </ul>
    <span
      v-if="maisAEsquerda"
      data-degrade="esquerda"
      aria-hidden="true"
      class="absolute inset-y-0 w-12 pointer-events-none start-0 bg-gradient-to-r from-n-surface-1 to-transparent rtl:bg-gradient-to-l md:hidden"
    />
    <span
      v-if="maisADireita"
      data-degrade="direita"
      aria-hidden="true"
      class="absolute inset-y-0 w-12 pointer-events-none end-0 bg-gradient-to-l from-n-surface-1 to-transparent rtl:bg-gradient-to-r md:hidden"
    />
  </nav>
</template>
