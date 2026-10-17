<script setup>
// O que impede o envio, com o que fazer (#1716): produto que acabou, catálogo
// que não respondeu.
defineProps({
  texto: { type: String, required: true },
});
</script>

<template>
  <div
    role="alert"
    class="flex gap-2 p-3 text-sm rounded-xl bg-n-ruby-2 text-n-ruby-11"
    data-aviso-do-envio
  >
    <span
      class="i-lucide-circle-alert size-4 mt-0.5 shrink-0"
      aria-hidden="true"
    />
    <span>{{ texto }}</span>
  </div>
</template>
