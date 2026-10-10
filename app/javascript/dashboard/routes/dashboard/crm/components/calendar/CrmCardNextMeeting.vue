<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { startOfDay } from 'date-fns';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import { resolveMeetingLocation } from '../../helpers/meetingLocation';
import {
  confirmationMeta,
  formatBookingTime,
} from '../../helpers/meetingNotices';
import CrmMeetingDayActions from './CrmMeetingDayActions.vue';

// A próxima reunião do card (#1193, J4-A1/A5): quando, onde, o número e a
// resposta do cliente, com "Chamar no WhatsApp" e "Lembrar". Sem reunião
// marcada de hoje em diante, não mostra nada. Só lê; erro também não mostra.
const props = defineProps({
  cardId: { type: [String, Number], required: true },
});

const { t, locale } = useI18n();
const route = useRoute();
const accountId = computed(() => route.params.accountId);
const meeting = ref(null);
let requestId = 0;

const load = async () => {
  requestId += 1;
  const current = requestId;
  meeting.value = null;
  if (!accountId.value || !props.cardId) return;
  try {
    const { data } = await crmMeetingsAPI.index(accountId.value, {
      card_id: props.cardId,
      status: 'scheduled',
      from: startOfDay(new Date()).toISOString(),
      per_page: 1,
    });
    const next = data?.payload?.[0];
    if (!next || current !== requestId) return;
    const detail = await crmMeetingsAPI.show(accountId.value, next.id);
    if (current === requestId) meeting.value = detail.data?.payload || null;
  } catch {
    if (current === requestId) meeting.value = null;
  }
};

watch(() => props.cardId, load, { immediate: true });

const location = computed(() => resolveMeetingLocation(meeting.value || {}));
const when = computed(() =>
  formatBookingTime(meeting.value?.starts_at, locale.value)
);
const status = computed(() =>
  meeting.value?.booking
    ? confirmationMeta(meeting.value.confirmation_status)
    : null
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="meeting"
    data-test="card-next-meeting"
    class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-3"
    :aria-label="t('CRM_KANBAN.CALENDAR.MEETING_DAY.NEXT_MEETING')"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.NEXT_MEETING') }}
      </p>
      <span
        v-if="status"
        data-test="card-next-meeting-status"
        class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium"
        :class="status.className"
      >
        <span class="size-3.5" :class="status.icon" aria-hidden="true" />
        {{ t(`CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.${status.key}`) }}
      </span>
    </div>
    <p class="mb-0 flex items-center gap-2 text-sm text-n-slate-12">
      <span class="i-lucide-clock size-4 text-n-slate-10" aria-hidden="true" />
      {{ when }}
    </p>
    <p
      v-if="location.isInternal"
      class="mb-0 flex items-center gap-2 text-sm text-n-slate-12"
    >
      <span class="size-4 text-n-slate-10" :class="location.icon" />
      {{ t(location.labelKey) }}
    </p>
    <CrmMeetingDayActions :meeting="meeting" :account-id="accountId" />
  </section>
</template>
