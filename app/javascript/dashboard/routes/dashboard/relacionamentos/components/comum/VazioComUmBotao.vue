<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — tela vazia da casa: uma frase e um botão. O texto das duas coisas vem
// de quem usa (cada tela diz o seu).
defineProps({
  frase: { type: String, required: true },
  botao: { type: String, required: true },
});
const emit = defineEmits(['acao']);
</script>

<template>
  <div
    data-vazio
    class="flex flex-col items-center gap-5 p-10 text-center border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-lg text-n-slate-12">{{ frase }}</p>
    <Button :label="botao" size="lg" @click="emit('acao')" />
  </div>
</template>
