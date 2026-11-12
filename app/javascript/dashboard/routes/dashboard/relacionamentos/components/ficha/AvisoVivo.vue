<script setup>
// #2894 — a região viva da ficha, só para o leitor de tela. Fica na página desde
// o início (uma região que nasce junto com o texto não é anunciada) e recebe o
// texto depois: carregando e o resultado de cada ação.
defineProps({
  texto: { type: String, default: '' },
});
</script>

<template>
  <div
    data-relacionamentos="aviso-vivo"
    role="status"
    aria-live="polite"
    class="sr-only"
  >
    {{ texto }}
  </div>
</template>
