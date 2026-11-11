<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — o vazio de dentro de uma seção da ficha: a frase em cinza e um botão
// discreto, alinhados à esquerda, sem cartão dentro do cartão. O botão preenchido
// da tela é só o "Conversar" do cabeçalho.
defineProps({
  frase: { type: String, required: true },
  botao: { type: String, required: true },
});
const emit = defineEmits(['acao']);
</script>

<template>
  <div data-vazio class="flex flex-col items-start gap-3">
    <p class="m-0 text-base text-n-slate-11">{{ frase }}</p>
    <Button slate faded class="min-h-11" :label="botao" @click="emit('acao')" />
  </div>
</template>
