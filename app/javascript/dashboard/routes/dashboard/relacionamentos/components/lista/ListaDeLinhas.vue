<script setup>
// #2894 — o cartão único da lista: linhas com divisórias suaves. Cada tela
// põe as suas linhas no slot.
</script>

<template>
  <ul
    class="m-0 min-w-0 overflow-hidden list-none border divide-y p-0 rounded-2xl border-n-weak bg-n-solid-1 divide-n-weak/60"
  >
    <slot />
  </ul>
</template>
