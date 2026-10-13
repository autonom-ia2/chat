<script setup>
import { computed } from 'vue';
import { partesDoTexto, SINAIS } from './modeloPronto';

// #1459 — o texto de uma mensagem pronta com cada campo variável à vista como
// uma pastilha neutra, no lugar do "{{1}}" cru.
const props = defineProps({
  texto: { type: String, default: '' },
});

const partes = computed(() => partesDoTexto(props.texto));
</script>

<template>
  <span>
    <template v-for="(parte, indice) in partes" :key="indice">
      <span
        v-if="parte.campo"
        data-campo-variavel
        class="mx-0.5 inline-block rounded-md bg-n-alpha-2 px-1.5 align-baseline text-xs font-semibold leading-5 text-n-slate-11"
      >
        {{ SINAIS.reticencias }}
      </span>
      <template v-else>{{ parte.texto }}</template>
    </template>
  </span>
</template>
