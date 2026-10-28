<script setup>
// #2138 — um bloco do painel: título curto (maior e mais forte que o conteúdo,
// sem caixa alta) e o conteúdo. Bloco sem conteúdo não é desenhado por quem usa.
// #2202 (PR 3): com `focavel`, o título recebe o foco quando outro bloco some
// com o foco dentro (o leitor de tela ouve onde a pessoa está).
import { ref } from 'vue';

defineProps({
  titulo: { type: String, default: '' },
  focavel: { type: Boolean, default: false },
});

const cabecalho = ref(null);
const focarTitulo = () => cabecalho.value?.focus({ preventScroll: true });

defineExpose({ focarTitulo });
</script>

<template>
  <section
    class="flex flex-col gap-2 px-4 py-4 border-t border-n-weak first:border-t-0"
  >
    <h3
      v-if="titulo"
      ref="cabecalho"
      :tabindex="focavel ? -1 : undefined"
      class="m-0 text-base font-semibold leading-6 text-n-slate-12"
      :class="
        focavel
          ? 'rounded focus:outline focus:outline-2 focus:outline-offset-2 focus:outline-n-brand'
          : ''
      "
    >
      {{ titulo }}
    </h3>
    <slot />
  </section>
</template>
