<script setup>
// Aviso curto da conferência automática (#1394): o modelo que estava em análise
// ficou pronto ou foi recusado. Discreto, lido pelo leitor de tela (aria-live).
defineProps({
  // [{ nome, situacao: 'pronto' | 'recusado' }]
  mudancas: { type: Array, default: () => [] },
});
</script>

<template>
  <!-- Sem aviso, fica fora do layout (sr-only, absoluto) mas presente para o leitor de tela. -->
  <div
    data-aviso-de-situacao
    role="status"
    aria-live="polite"
    :class="mudancas.length ? 'flex flex-col gap-2' : 'sr-only'"
  >
    <p
      v-for="mudanca in mudancas"
      :key="`${mudanca.nome}-${mudanca.situacao}`"
      :data-mudanca="mudanca.situacao"
      class="flex items-center gap-2 px-4 py-2 mb-0 text-sm rounded-xl bg-n-slate-2 text-n-slate-12"
    >
      <span
        class="size-4 shrink-0"
        :class="
          mudanca.situacao === 'pronto'
            ? 'i-lucide-circle-check text-n-teal-10'
            : 'i-lucide-circle-x text-n-ruby-10'
        "
        aria-hidden="true"
      />
      {{
        mudanca.situacao === 'pronto'
          ? $t('MODELOS_WHATSAPP.CONFERENCIA_AUTOMATICA.PRONTO', {
              nome: mudanca.nome,
            })
          : $t('MODELOS_WHATSAPP.CONFERENCIA_AUTOMATICA.RECUSADO', {
              nome: mudanca.nome,
            })
      }}
    </p>
  </div>
</template>
