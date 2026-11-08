<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

import MessageStatus from './MessageStatus.vue';
import Icon from 'next/icon/Icon.vue';
import { useInbox } from 'dashboard/composables/useInbox';
import { useMessageContext } from './provider.js';
import {
  useDicaDaHoraDaPele,
  useHoraDaPele,
} from '../conversa-canal/useHoraDaPele';
import { usePele } from '../conversa-canal/pele';
import { foiEditada } from '../conversa-canal/marcasDaMensagem';
import RotuloEditada from '../conversa-canal/RotuloEditada.vue';
import { ehEcoDoCelular } from '../conversa-canal/ecoDoCelular';

import { MESSAGE_STATUS, MESSAGE_TYPES } from './constants';

const exactTimestamp = useExactTimestamp();
const { t } = useI18n();

const {
  isAFacebookInbox,
  isALineChannel,
  isAPIInbox,
  isASmsInbox,
  isATelegramChannel,
  isATwilioChannel,
  isAWebWidgetInbox,
  isAWhatsAppChannel,
  isAnEmailChannel,
  isAnInstagramChannel,
  isATiktokChannel,
} = useInbox();

const {
  status,
  isPrivate,
  createdAt,
  sourceId,
  messageType,
  contentAttributes,
} = useMessageContext();

// #1702: com a pele do canal, "14:32" no fuso da conta, como no app.
const horaDaPele = useHoraDaPele(createdAt);
const readableTime = computed(
  () => horaDaPele.value || messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);

// #1702: com a pele, a dica também no fuso da conta (a hora do balão já está nele).
const dicaDaPele = useDicaDaHoraDaPele(createdAt);
const exactTime = computed(
  () => dicaDaPele.value || exactTimestamp(createdAt.value)
);

// #1702: com a pele, "Editada" antes da hora, como no app (clique mostra as versões).
const pele = usePele();
const editada = computed(
  () => Boolean(pele.value) && foiEditada(contentAttributes.value)
);

// #1702: com a pele, a que falhou mostra o ícone vermelho do app no lugar dos tiques.
const falhou = computed(
  () =>
    Boolean(pele.value) &&
    !isPrivate.value &&
    status.value === MESSAGE_STATUS.FAILED
);

// #1941: enviada pelo app do celular (eco): um 📱 pequeno ao lado da hora, nos três WhatsApp.
const peloCelular = computed(() => ehEcoDoCelular(contentAttributes.value));
const CELULAR = '📱';

// WhatsApp Híbrido (chat#1067): mensagem que saiu pelo WhatsApp API em vez da conexão oficial.
const transportLabel = computed(() => {
  if (contentAttributes.value?.whatsappTransport !== 'web') return '';
  return contentAttributes.value?.whatsappTransportFallback
    ? t('CONVERSATION.WHATSAPP_TRANSPORT.WEB_FALLBACK')
    : t('CONVERSATION.WHATSAPP_TRANSPORT.WEB');
});

const showStatusIndicator = computed(() => {
  if (isPrivate.value) return false;
  // Don't show status for failed messages, we already show error message
  if (status.value === MESSAGE_STATUS.FAILED) return false;
  // Don't show status for deleted messages
  if (contentAttributes.value?.deleted) return false;

  if (messageType.value === MESSAGE_TYPES.OUTGOING) return true;
  if (messageType.value === MESSAGE_TYPES.TEMPLATE) return true;

  return false;
});

const isSent = computed(() => {
  if (!showStatusIndicator.value) return false;

  // Messages will be marked as sent for the Email channel if they have a source ID.
  if (isAnEmailChannel.value) return !!sourceId.value;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isASmsInbox.value ||
    isATelegramChannel.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.SENT;
  }

  // API inbox messages use real sent/delivered/read status values from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.SENT;

  // All messages will be mark as sent for the Line channel, as there is no source ID.
  if (isALineChannel.value) return true;

  return false;
});

const isDelivered = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isASmsInbox.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.DELIVERED;
  }
  // API inbox messages use real delivered status from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.DELIVERED;
  // All messages marked as delivered for the web widget inbox once they are sent.
  if (isAWebWidgetInbox.value) {
    return status.value === MESSAGE_STATUS.SENT;
  }
  if (isALineChannel.value) {
    return status.value === MESSAGE_STATUS.DELIVERED;
  }

  return false;
});

const isRead = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.READ;
  }

  if (isAWebWidgetInbox.value || isAPIInbox.value) {
    return status.value === MESSAGE_STATUS.READ;
  }

  return false;
});

const statusToShow = computed(() => {
  if (isRead.value) return MESSAGE_STATUS.READ;
  if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
  if (isSent.value) return MESSAGE_STATUS.SENT;

  return MESSAGE_STATUS.PROGRESS;
});
</script>

<template>
  <div class="text-xs flex items-center gap-1.5">
    <RotuloEditada v-if="editada" :atributos="contentAttributes" />
    <span
      v-if="peloCelular"
      v-tooltip.top="t('CONVERSA_CANAL.ECO_DO_CELULAR.ENVIADA_PELO_CELULAR')"
      role="img"
      :aria-label="t('CONVERSA_CANAL.ECO_DO_CELULAR.ENVIADA_PELO_CELULAR')"
      class="text-[11px] leading-none select-none"
      data-eco-do-celular
    >
      {{ CELULAR }}
    </span>
    <div class="inline">
      <time
        v-tooltip.top="{
          content: exactTime,
          delay: { show: 500, hide: 0 },
        }"
        class="inline"
      >
        {{ readableTime }}
      </time>
    </div>
    <Icon v-if="isPrivate" icon="i-lucide-lock-keyhole" class="size-3" />
    <span v-if="transportLabel" class="whitespace-nowrap" data-transporte>
      {{ transportLabel }}
    </span>
    <MessageStatus v-if="showStatusIndicator" :status="statusToShow" />
    <span
      v-if="falhou"
      v-tooltip.top-start="t('CONVERSA_CANAL.FALHA.NAO_ENVIADA')"
      role="img"
      :aria-label="t('CONVERSA_CANAL.FALHA.NAO_ENVIADA')"
      class="i-ph-warning-circle-fill size-4 shrink-0 text-[#EA0038] dark:text-[#F15C6D]"
      data-falha-do-whatsapp
    />
  </div>
</template>
`
