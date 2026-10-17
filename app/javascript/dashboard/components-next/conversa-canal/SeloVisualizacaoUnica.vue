<script setup>
// Rótulo da visualização única (#1702): o "1" num círculo e "Visualização única",
// como no WhatsApp, em cima da mídia. A mídia continua aparecendo: o atendimento
// guarda o que o cliente mandou (decisão do Rodrigo, 16/10). Quem decide se aparece
// é o balão (Base.vue): só com a pele e com a marca no anexo.

// O número do ícone do WhatsApp ("ver uma vez"), não é texto para traduzir.
const UMA_VEZ = 1;
</script>

<template>
  <div
    class="flex items-center gap-1.5 px-1 pb-1 text-[13px] leading-[18px] text-[#008069] dark:text-[#06CF9C]"
    data-visualizacao-unica
  >
    <span
      aria-hidden="true"
      class="inline-flex items-center justify-center shrink-0 size-[18px] rounded-full border-[1.5px] border-current text-[10px] font-bold leading-none"
    >
      {{ UMA_VEZ }}
    </span>
    <span>{{ $t('CONVERSA_CANAL.VISUALIZACAO_UNICA.ROTULO') }}</span>
  </div>
</template>
