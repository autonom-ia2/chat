<script setup>
// O "biquinho" do balão do WhatsApp (#1702): um triângulo no canto de cima, do lado
// de quem falou, só no primeiro balão de cada sequência. Desenho nosso, mesma forma.
// Encosta 1 px por dentro do balão para não sobrar emenda entre os dois.
defineProps({
  lado: { type: String, required: true },
});
</script>

<template>
  <svg
    aria-hidden="true"
    viewBox="0 0 8 13"
    width="8"
    height="13"
    class="absolute top-0 fill-current [filter:drop-shadow(0_1px_0.5px_rgba(11,20,26,0.13))]"
    :class="
      lado === 'right'
        ? 'ltr:-right-[7px] rtl:-left-[7px] rtl:-scale-x-100'
        : 'ltr:-left-[7px] rtl:-right-[7px] ltr:-scale-x-100'
    "
  >
    <path d="M0 0h5.2c2.5 0 3.3 1.6 1.9 3.7L0 13V0Z" />
  </svg>
</template>
