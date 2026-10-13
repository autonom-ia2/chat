<script setup>
// Caixas do WhatsApp oficial que precisam reconectar: aparecem desativadas na
// escolha, e aqui o motivo e o caminho para resolver.
defineProps({
  caixas: { type: Array, required: true },
});
</script>

<template>
  <ul
    v-if="caixas.length"
    data-ponte-reconectar
    class="flex flex-col gap-2 p-0 m-0 list-none"
  >
    <li
      v-for="caixa in caixas"
      :key="caixa.id"
      class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-n-slate-11"
    >
      <span class="i-lucide-plug-zap size-4 text-n-amber-11" aria-hidden="true" />
      {{ $t('MODELOS_WHATSAPP.PONTE.RECONECTAR_MOTIVO', { nome: caixa.nome }) }}
      <router-link
        :to="{ name: 'settings_inbox_show', params: { inboxId: caixa.id } }"
        class="inline-flex items-center font-medium min-h-11 text-n-blue-11 hover:underline"
      >
        {{ $t('MODELOS_WHATSAPP.PONTE.RECONECTAR') }}
      </router-link>
    </li>
  </ul>
</template>
