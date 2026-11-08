<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// Seus posts (#2302): todo estado vazio da página tem o mesmo desenho: um ícone, uma frase, uma linha de apoio, um
// botão e, no máximo, um link (o slot).
defineProps({
  icon: { type: String, required: true },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  botao: { type: String, default: '' },
  botaoIcon: { type: String, default: '' },
});
const emit = defineEmits(['acao']);
</script>

<template>
  <!-- O mesmo vazio do painel de Anúncios: alinhado à esquerda, ícone, frase, apoio e um botão. -->
  <div
    class="flex flex-col items-start gap-4 rounded-2xl bg-n-solid-1 px-6 py-8 ring-1 ring-inset ring-n-weak"
  >
    <span :class="icon" class="size-8 text-n-slate-10" aria-hidden="true" />
    <div class="flex max-w-xl flex-col gap-1">
      <h2 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ titulo }}
      </h2>
      <p v-if="texto" class="m-0 text-sm text-n-slate-11">
        {{ texto }}
      </p>
    </div>
    <Button
      v-if="botao"
      :icon="botaoIcon"
      :label="botao"
      class="!min-h-11 !rounded-xl"
      @click="emit('acao')"
    />
    <slot />
  </div>
</template>
