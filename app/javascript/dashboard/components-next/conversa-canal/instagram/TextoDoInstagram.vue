<script setup>
// Balão de texto do Direct (#2079): 15 px, 8×12 de respiro, cantos do grupo.
import { computed } from 'vue';
import { BALAO_DE_TEXTO, ENVIADO, RECEBIDO } from './visualInstagram';

const props = defineProps({
  texto: { type: String, required: true },
  enviada: { type: Boolean, default: false },
  cantos: { type: Object, required: true },
});

const cor = computed(() => (props.enviada ? ENVIADO : RECEBIDO));
</script>

<template>
  <div :class="[BALAO_DE_TEXTO, cor]" :style="cantos" dir="auto">
    {{ texto }}
  </div>
</template>
