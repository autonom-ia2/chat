<script setup>
// Modelo escolhido ainda em análise: dá para montar e agendar; enviar agora só
// depois que o WhatsApp aprovar.
defineProps({
  modelo: { type: Object, default: null },
});
</script>

<template>
  <p
    v-if="modelo?.situacao === 'em_analise'"
    data-ponte-em-analise
    class="flex gap-2 p-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
  >
    <span
      class="i-lucide-clock-3 size-4 mt-0.5 shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    {{ $t('MODELOS_WHATSAPP.PONTE.EM_ANALISE', { nome: modelo.nome }) }}
  </p>
</template>
