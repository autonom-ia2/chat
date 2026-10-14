<script setup>
// Pedido de localização: `{ type: 'location_request' }`, com o corpo em `content`. O botão é a imagem do que o
// cliente vê no WhatsApp; a resposta dele chega como localização, em mensagem própria.
// Só o WhatsApp oficial (Cloud) leva o botão: nos outros canais o cliente recebe só o corpo, e a bolha não o desenha.
// Limite: no Híbrido, o plano B pode ter levado só o texto, e a bolha não sabe disso (ver o doc da entrega).
import { useI18n } from 'vue-i18n';
import { useInbox } from 'dashboard/composables/useInbox';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';

const { inboxId } = useMessageContext();
const { isAWhatsAppCloudChannel } = useInbox(inboxId?.value);
const { t } = useI18n();
</script>

<template>
  <Frame bubble-name="rich-location-request">
    <div class="flex flex-col gap-1.5">
      <ActionRow
        v-if="isAWhatsAppCloudChannel"
        icon="i-lucide-map-pin"
        :label="t('RICH_MESSAGE.LOCATION_REQUEST.BUTTON')"
      >
        {{ t('RICH_MESSAGE.LOCATION_REQUEST.BUTTON') }}
        <span class="sr-only">
          {{ t('RICH_MESSAGE.LOCATION_REQUEST.BUTTON_HINT') }}
        </span>
      </ActionRow>
      <div class="text-xs text-n-slate-11 break-words">
        {{ t('RICH_MESSAGE.LOCATION_REQUEST.CAPTION') }}
      </div>
    </div>
  </Frame>
</template>
