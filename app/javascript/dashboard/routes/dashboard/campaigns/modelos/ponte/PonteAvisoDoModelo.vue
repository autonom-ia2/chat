<script setup>
import PonteSinalDoModelo from './PonteSinalDoModelo.vue';

// Modelo escolhido ainda em análise: dá para montar e agendar; enviar agora só
// depois que o WhatsApp aprovar. Pronto com nota ruim: o aviso do sinal (#1338).
defineProps({
  modelo: { type: Object, default: null },
});
</script>

<template>
  <!-- Sem nada para mostrar, o embrulho não ocupa lugar (display: contents). -->
  <div class="contents">
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
    <PonteSinalDoModelo :modelo="modelo" />
  </div>
</template>
