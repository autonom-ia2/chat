<script setup>
// Oferta por tempo limitado na prévia: o título, o "vale até" que a campanha
// escolheu (#1456; na tela de Modelos, um exemplo da contagem, porque a data é
// dada no envio) e o cupom, como o WhatsApp mostra em cima do texto.
defineProps({
  oferta: { type: Object, required: true },
});
</script>

<template>
  <div
    data-celular-oferta
    class="flex items-start gap-2.5 p-2.5 rounded-lg bg-n-slate-2"
  >
    <span
      class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-ruby-3 text-n-ruby-11"
    >
      <span class="i-lucide-timer size-5" aria-hidden="true" />
    </span>
    <span class="flex flex-col min-w-0">
      <span class="text-sm font-semibold break-words text-n-slate-12">
        {{ oferta.titulo || $t('MODELOS_WHATSAPP.CELULAR.VAZIO') }}
      </span>
      <span v-if="oferta.validade" class="text-xs text-n-ruby-11">
        {{
          $t('MODELOS_WHATSAPP.CELULAR.OFERTA_VALE_ATE', {
            data: oferta.validade,
          })
        }}
      </span>
      <template v-if="oferta.cupom">
        <span v-if="!oferta.validade" class="text-xs text-n-ruby-11">
          {{ $t('MODELOS_WHATSAPP.CELULAR.OFERTA_CONTAGEM') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.CELULAR.CUPOM', { cupom: oferta.cupom }) }}
        </span>
      </template>
    </span>
  </div>
</template>
