<script setup>
// O "biquinho" do balão do WhatsApp (#1702): um triângulo no canto de cima, do lado
// de quem falou, só no primeiro balão de cada sequência. Desenho nosso, mesma forma.
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
    class="absolute top-0 fill-current"
    :class="
      lado === 'right'
        ? 'ltr:-right-2 rtl:-left-2 rtl:-scale-x-100'
        : 'ltr:-left-2 rtl:-right-2 ltr:-scale-x-100'
    "
  >
    <path d="M0 0h5.2c2.5 0 3.3 1.6 1.9 3.7L0 13V0Z" />
  </svg>
</template>
