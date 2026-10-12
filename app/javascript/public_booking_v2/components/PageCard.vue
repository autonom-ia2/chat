<script setup>
// O cartão branco onde toda tela da página aparece. A prévia do painel (#1289) usa este mesmo cartão, para a
// prévia nunca ficar diferente da página de verdade.
</script>

<template>
  <div
    data-page-card
    class="rounded-3xl border border-solid border-bk-line bg-bk-card p-5 shadow-sm sm:p-8"
  >
    <slot />
  </div>
</template>
