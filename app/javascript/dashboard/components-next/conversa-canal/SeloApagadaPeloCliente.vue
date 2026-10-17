<script setup>
// "🚫 Apagada pelo cliente" no topo do balão (#1702): o desenho do WhatsApp para
// mensagem apagada (o círculo cortado, em cinza e itálico), mas o conteúdo continua
// embaixo, à vista da equipe (decisão de negócio: guardamos o que o cliente mandou).
// O cliente já não vê a mensagem; a dica diz isso a quem passa o mouse ou usa leitor.
</script>

<template>
  <div
    class="flex items-center gap-1 px-1 pb-0.5 text-[13px] leading-[18px] italic text-[#666666] dark:text-[#A7A8A8] [[data-bubble-name=text]_&]:px-0"
    :title="$t('CONVERSA_CANAL.APAGADA.AJUDA')"
    data-apagada-pelo-cliente
  >
    <span class="i-ph-prohibit-bold size-3.5 shrink-0" aria-hidden="true" />
    <span>{{ $t('CONVERSA_CANAL.APAGADA.PELO_CLIENTE') }}</span>
    <span class="sr-only">{{ $t('CONVERSA_CANAL.APAGADA.AJUDA') }}</span>
  </div>
</template>
