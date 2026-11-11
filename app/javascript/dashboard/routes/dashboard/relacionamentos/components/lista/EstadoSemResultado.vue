<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — lista sem ninguém (grupo vazio, busca ou filtro sem resultado): uma
// frase e, quando há como sair dali, um botão discreto. A conta vazia usa
// VazioComUmBotao, com o botão principal. Quem anuncia a frase ao leitor de tela
// é a região viva da página (ListaPage): um `role="status"` que nasce junto com
// o texto não é anunciado.
defineProps({
  frase: { type: String, required: true },
  botao: { type: String, default: '' },
});
const emit = defineEmits(['acao']);
</script>

<template>
  <div
    data-relacionamentos="vazio"
    class="flex flex-col items-center gap-4 p-10 text-center border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-lg text-n-slate-12">{{ frase }}</p>
    <Button
      v-if="botao"
      slate
      faded
      class="min-h-11"
      :label="botao"
      @click="emit('acao')"
    />
  </div>
</template>
