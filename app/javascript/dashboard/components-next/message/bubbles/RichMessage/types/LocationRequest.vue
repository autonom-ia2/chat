<script setup>
// Pedido de localização: `{ type: 'location_request' }`, com o corpo em `content`. O botão é a imagem do que o
// cliente vê no WhatsApp; a resposta dele chega como localização, em mensagem própria.
import { useI18n } from 'vue-i18n';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';

const { t } = useI18n();
</script>

<template>
  <Frame bubble-name="rich-location-request">
    <div class="flex flex-col gap-1.5">
      <ActionRow
        icon="i-lucide-map-pin"
        :label="t('RICH_MESSAGE.LOCATION_REQUEST.BUTTON')"
      />
      <div class="text-xs text-n-slate-11 break-words">
        {{ t('RICH_MESSAGE.LOCATION_REQUEST.CAPTION') }}
      </div>
    </div>
  </Frame>
</template>
