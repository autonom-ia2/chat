<script setup>
// Convite de evento (chat#1709, rodada 2): `{ type: 'event', start_at, end_at?, location_name?, description? }`, com o
// nome do evento em `content`. Mostra o convite como o cliente recebeu (data e hora no fuso da conta, local e
// descrição) e as respostas ("Vou / Não vou / Talvez") gravadas na própria mensagem (eventAnswer.js). Sem botão de
// cancelar: o motor do WhatsApp não cancela evento.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import { eventDateLabel, eventResponseCounts } from '../eventAnswer.js';

const { contentAttributes } = useMessageContext();
const { t, locale } = useI18n();
const currentAccountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');

// Tudo vem de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});
const timeZone = computed(() =>
  fusoDaConta(getAccount.value?.(currentAccountId.value))
);
const dateLabel = (isoText, base) =>
  eventDateLabel(
    textOf(isoText),
    timeZone.value,
    String(locale.value || '').replace('_', '-')
  ) || base;

const startLabel = computed(() => dateLabel(richMessage.value.startAt, ''));
const endLabel = computed(() => dateLabel(richMessage.value.endAt, ''));
const locationName = computed(() => textOf(richMessage.value.locationName));
const description = computed(() => textOf(richMessage.value.description));
const counts = computed(() =>
  eventResponseCounts(contentAttributes.value?.eventResponses)
);
const hasResponses = computed(
  () => counts.value.going + counts.value.not_going + counts.value.maybe > 0
);
</script>

<template>
  <Frame bubble-name="rich-event">
    <div class="flex flex-col gap-1.5 text-sm text-n-slate-12">
      <span class="sr-only">{{ t('RICH_MESSAGE.EVENT.MIRROR') }}</span>
      <div v-if="startLabel" data-event-when class="flex items-start gap-1.5">
        <Icon icon="i-lucide-calendar" class="size-4 flex-shrink-0 mt-0.5" />
        <span class="break-words">
          {{
            endLabel
              ? t('RICH_MESSAGE.EVENT.WHEN_RANGE', {
                  start: startLabel,
                  end: endLabel,
                })
              : startLabel
          }}
        </span>
      </div>
      <div
        v-if="locationName"
        data-event-where
        class="flex items-start gap-1.5"
      >
        <Icon icon="i-lucide-map-pin" class="size-4 flex-shrink-0 mt-0.5" />
        <span class="break-words">{{ locationName }}</span>
      </div>
      <p
        v-if="description"
        class="text-n-slate-11 break-words whitespace-pre-wrap"
      >
        {{ description }}
      </p>
      <div
        data-event-responses
        class="text-xs font-medium text-n-slate-11 break-words"
      >
        {{
          hasResponses
            ? t('RICH_MESSAGE.EVENT.RESPONSES', {
                going: counts.going,
                notGoing: counts.not_going,
                maybe: counts.maybe,
              })
            : t('RICH_MESSAGE.EVENT.NO_RESPONSE')
        }}
      </div>
    </div>
  </Frame>
</template>
