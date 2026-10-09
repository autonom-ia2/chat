<script setup>
import {
  DOT,
  MINUS,
} from 'dashboard/components-next/CampaignJourney/textMarks';
// Passo 3 — Revisar e agendar (#993, PRD §6.4, D3, D8, B8). Blocks with "Alterar" (built by
// the page for each channel), the CRM line, when (now, or date and time in the account time
// zone), the exact "vão receber" from POST campaign_journey/recipient_previews with the
// reasons of who is left out (each person once), "Enviar teste para mim" for e-mail and a
// final confirmation with the number. No batches: everyone at the chosen time.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { formatInZone, isFutureSchedule, scheduleToUtc } from './scheduleTime';
import { toLocaleTag, formatNumber } from 'dashboard/helper/localeTag';

const props = defineProps({
  draft: { type: Object, required: true },
  // [{ key, step, title, main, detail }]
  blocks: { type: Array, required: true },
  channelLabel: { type: String, required: true },
  onChannelLabel: { type: String, required: true },
  crmTag: { type: String, required: true },
  // Audience count on the channel while the server preview is not there.
  reach: { type: Number, default: 0 },
  // { total, receive, reasons: { opted_out: 2, ... } } from recipient_previews, or null.
  preview: { type: Object, default: null },
  // E-mail readiness checks [{ key, ok }] (send_readiness of the e-mail engine).
  checks: { type: Array, default: () => [] },
  showTestSend: { type: Boolean, default: false },
  isTestSending: { type: Boolean, default: false },
  timeZone: { type: String, required: true },
  isSubmitting: { type: Boolean, default: false },
  errorMessage: { type: String, default: '' },
});

const emit = defineEmits(['update', 'go', 'back', 'submit', 'testSend']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const confirmRef = ref(null);

const REASON_ORDER = [
  'channel_disabled',
  'opted_out',
  'unsubscribed',
  'bounced',
  'suppressed',
  'missing_variables',
];

const isLater = computed(() => props.draft.when === 'later');
const total = computed(() => props.preview?.total ?? props.reach);
const receivers = computed(() => props.preview?.receive ?? props.reach);
const reasons = computed(() =>
  REASON_ORDER.map(key => ({
    key,
    count: Number(props.preview?.reasons?.[key]) || 0,
  })).filter(reason => reason.count > 0)
);
const isScheduleValid = computed(
  () =>
    !isLater.value || isFutureSchedule(props.draft.scheduledAt, props.timeZone)
);
const whenText = computed(() => {
  if (!isLater.value || !isScheduleValid.value) return '';
  return formatInZone(
    scheduleToUtc(props.draft.scheduledAt, props.timeZone),
    props.timeZone,
    toLocaleTag(locale.value)
  );
});
const actionLabel = computed(() =>
  isLater.value ? t(`${NS}.SCHEDULE`) : t(`${NS}.SEND_NOW`)
);
const confirmTitle = computed(() =>
  t(
    isLater.value ? `${NS}.CONFIRM_LATER` : `${NS}.CONFIRM_NOW`,
    { count: n(receivers.value) },
    receivers.value
  )
);
const confirmText = computed(() =>
  isLater.value
    ? t(`${NS}.CONFIRM_LATER_TEXT`, { when: whenText.value })
    : t(`${NS}.CONFIRM_NOW_TEXT`)
);
const isBlocked = computed(() => props.checks.some(check => !check.ok));

const openConfirmation = () => {
  if (!isScheduleValid.value || isBlocked.value) return;
  confirmRef.value?.open();
};

const submit = () => {
  confirmRef.value?.close();
  emit('submit');
};
</script>

<template>
  <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
    <section
      class="flex min-w-0 flex-col rounded-2xl border border-n-weak bg-n-solid-1 px-4 shadow-sm sm:px-5"
      data-test="review"
    >
      <div
        v-for="block in blocks"
        :key="block.key"
        class="flex items-start justify-between gap-3 border-b border-n-weak py-4"
        :data-review-block="block.key"
      >
        <div class="min-w-0">
          <p class="m-0 text-xs font-semibold uppercase text-n-slate-11">
            {{ block.title }}
          </p>
          <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
            {{ block.main }}
          </p>
          <p class="m-0 break-words text-xs text-n-slate-11">
            {{ block.detail }}
          </p>
        </div>
        <Button
          :label="t(`${NS}.CHANGE`)"
          :aria-label="t(`${NS}.CHANGE_ARIA`, { block: block.title })"
          variant="ghost"
          size="sm"
          class="!min-h-11 shrink-0"
          @click="emit('go', block.step)"
        />
      </div>
      <p
        class="m-0 flex flex-wrap items-center gap-2 border-b border-n-weak py-4 text-sm text-n-slate-12"
        data-test="review-crm"
      >
        <span
          class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-semibold text-n-blue-11"
        >
          {{ t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.CRM_BADGE') }}
        </span>
        {{ t(`${NS}.CRM`, { tag: crmTag }) }}
      </p>
      <fieldset class="m-0 flex flex-col gap-3 border-0 p-0 py-4">
        <legend class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.WHEN`) }}
        </legend>
        <div class="flex flex-wrap gap-2" role="radiogroup">
          <button
            v-for="option in ['now', 'later']"
            :key="option"
            type="button"
            role="radio"
            :aria-checked="draft.when === option"
            :data-when="option"
            class="min-h-11 rounded-xl border px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              draft.when === option
                ? 'border-n-blue-8 bg-n-blue-2 text-n-blue-11'
                : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-1'
            "
            @click="emit('update', { when: option })"
          >
            {{ option === 'now' ? t(`${NS}.NOW`) : t(`${NS}.LATER`) }}
          </button>
        </div>
        <Input
          v-if="isLater"
          :model-value="draft.scheduledAt"
          type="datetime-local"
          :label="t(`${NS}.DATE_LABEL`, { zone: timeZone })"
          :message="isScheduleValid ? '' : t(`${NS}.PAST`)"
          :message-type="isScheduleValid ? 'info' : 'error'"
          custom-input-class="!h-11"
          data-test="schedule-at"
          @update:model-value="scheduledAt => emit('update', { scheduledAt })"
        />
      </fieldset>
    </section>

    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm lg:sticky lg:top-4"
      data-test="review-aside"
    >
      <div class="rounded-xl bg-n-navy p-4 text-white">
        <p class="m-0 text-xs font-semibold uppercase opacity-80">
          {{ t(`${NS}.RECEIVE`) }}
        </p>
        <p
          class="m-0 text-4xl font-semibold tabular-nums"
          data-test="receivers"
        >
          {{ n(receivers) }}
        </p>
        <p class="m-0 text-sm opacity-80">
          {{ channelLabel }} {{ DOT }}
          {{ isLater ? whenText : t(`${NS}.NOW`) }}
        </p>
      </div>
      <dl class="m-0 flex flex-col gap-1 text-sm" data-test="review-counts">
        <div class="flex justify-between gap-3">
          <dt class="text-n-slate-11">{{ onChannelLabel }}</dt>
          <dd class="m-0 font-semibold tabular-nums">{{ n(total) }}</dd>
        </div>
        <div
          v-for="reason in reasons"
          :key="reason.key"
          class="flex justify-between gap-3"
          :data-reason="reason.key"
        >
          <dt class="text-n-slate-11">
            {{ t(`${NS}.REASONS.${reason.key.toUpperCase()}`) }}
          </dt>
          <dd class="m-0 tabular-nums">{{ MINUS }}{{ n(reason.count) }}</dd>
        </div>
      </dl>
      <ul
        v-if="checks.length"
        class="m-0 flex list-none flex-col gap-1 p-0 text-xs"
        data-test="review-checks"
      >
        <li
          v-for="check in checks"
          :key="check.key"
          class="flex items-center gap-2"
          :class="check.ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          <span
            :class="check.ok ? 'i-lucide-check' : 'i-lucide-x'"
            class="size-3.5 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${NS}.CHECKS.${check.key.toUpperCase()}`) }}
        </li>
      </ul>
      <Button
        v-if="showTestSend"
        :label="t(`${NS}.TEST_SEND`)"
        :is-loading="isTestSending"
        variant="outline"
        color="slate"
        class="!min-h-11 w-full justify-center !rounded-xl"
        data-test="test-send"
        @click="emit('testSend')"
      />
      <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <Button
        :label="actionLabel"
        :disabled="!isScheduleValid || !receivers || isBlocked || isSubmitting"
        :is-loading="isSubmitting"
        class="!min-h-11 w-full justify-center !rounded-xl"
        data-test="open-confirmation"
        @click="openConfirmation"
      />
      <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.EDIT_NOTE`) }}</p>
      <Button
        :label="t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.BACK')"
        variant="outline"
        color="slate"
        class="!min-h-11 w-full justify-center !rounded-xl"
        @click="emit('back')"
      />
    </aside>

    <Dialog
      ref="confirmRef"
      :title="confirmTitle"
      :description="confirmText"
      :confirm-button-label="actionLabel"
      :cancel-button-label="t(`${NS}.CONFIRM_BACK`)"
      @confirm="submit"
    />
  </div>
</template>
