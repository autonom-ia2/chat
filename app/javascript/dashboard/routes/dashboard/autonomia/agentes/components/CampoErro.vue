<script setup>
// #3211 — a mensagem de erro embaixo de um campo (dados da corretora e acesso à seguradora): ícone e texto em rubi,
// anunciada ao aparecer. `id` é o que o campo aponta no aria-describedby. Sem texto, nada aparece.
defineProps({
  id: { type: String, required: true },
  texto: { type: String, default: '' },
});
</script>

<template>
  <p
    v-if="texto"
    :id="id"
    role="alert"
    class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
  >
    <span class="i-lucide-circle-alert size-4 shrink-0" aria-hidden="true" />
    {{ texto }}
  </p>
</template>
