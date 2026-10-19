<script setup>
// Embaixo do campo Nome (#1823): como a etiqueta fica na prática — o `title`
// que vai para filtros, automações e API. Sem nada aproveitável: o aviso.
defineProps({
  tecnico: { type: String, default: '' },
  nomeDigitado: { type: String, default: '' },
  // Editar (#1823): o técnico não muda com o nome; só mostra.
  fixo: { type: Boolean, default: false },
});
</script>

<template>
  <p
    v-if="!fixo && nomeDigitado.trim() && tecnico.length < 2"
    class="w-full -mt-2 mb-3 text-label-small text-n-ruby-11"
    role="alert"
  >
    {{ $t('LABEL_MGMT.READABLE_NAME.TECHNICAL_EMPTY') }}
  </p>
  <p
    v-else-if="tecnico"
    class="w-full -mt-2 mb-3 text-label-small text-n-slate-11"
    aria-live="polite"
  >
    {{ $t('LABEL_MGMT.READABLE_NAME.TECHNICAL_PREVIEW') }}
    <code class="px-1 rounded bg-n-alpha-2 text-n-slate-12">{{ tecnico }}</code>
    <template v-if="fixo">
      {{ $t('LABEL_MGMT.READABLE_NAME.TECHNICAL_FIXED') }}
    </template>
  </p>
  <template v-else />
</template>
