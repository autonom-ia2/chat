<script setup>
import { computed } from 'vue';

// #1149 — ícone do canal da caixa, num quadrado de cor neutra.
const props = defineProps({
  canal: { type: String, default: '' },
  grande: { type: Boolean, default: false },
});

const ICONES = {
  whatsapp: 'i-ri-whatsapp-line',
  instagram: 'i-ri-instagram-line',
  email: 'i-lucide-mail',
  web_widget: 'i-lucide-globe',
};

const icone = computed(() => ICONES[props.canal] || 'i-lucide-inbox');
</script>

<template>
  <span
    class="grid shrink-0 place-items-center rounded-xl bg-n-alpha-2 text-n-slate-12"
    :class="grande ? 'size-12' : 'size-10'"
    aria-hidden="true"
  >
    <span :class="[icone, grande ? 'size-6' : 'size-5']" />
  </span>
</template>
