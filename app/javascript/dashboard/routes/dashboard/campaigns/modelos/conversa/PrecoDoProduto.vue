<script setup>
// O preço que o cliente vê (#1716). Em promoção (dentro do período, conferido
// no servidor), o preço cheio aparece riscado antes.
defineProps({
  // { preco, precoAntes }
  produto: { type: Object, required: true },
});
</script>

<template>
  <span data-preco-do-produto>
    <s v-if="produto.precoAntes" class="me-1 opacity-80">
      {{ produto.precoAntes }}
    </s>
    {{ produto.preco }}
  </span>
</template>
