<script setup>
// Passo 3 — Revisar e agendar (#993, PRD §6.4, D3). Blocks with "Alterar", the CRM line,
// when (now, or date and time in the account time zone), how many will receive it and
// a final confirmation with that number. No batches: everyone at the chosen time.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { formatInZone, isFutureSchedule, scheduleToUtc } from './scheduleTime';

const props = defineProps({
  audience: { type: Object, required: true },
  draft: { type: Object, required: true },
  channelLabel: { type: String, required: true },
  inboxName: { type: String, default: '' },
  templateName: { type: String, default: '' },
  bindingSummary: { type: String, default: '' },
  reach: { type: Number, default: 0 },
  excluded: { type: Number, default: null },
  timeZone: { type: String, required: true },
  isSubmitting: { type: Boolean, default: false },
  errorMessage: { type: String, default: '' },
});

const emit = defineEmits(['update', 'go', 'back', 'submit']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t, n, locale } = useI18n();
const confirmRef = ref(null);

const isLater = computed(() => props.draft.when === 'later');
const receivers = computed(() =>
  Math.max(0, props.reach - (props.excluded || 0))
);
const isScheduleValid = computed(
  () => !isLater.value || isFutureSchedule(props.draft.scheduledAt, props.timeZone)
);
const whenText = computed(() => {
  if (!isLater.value || !isScheduleValid.value) return '';
  return formatInZone(
    scheduleToUtc(props.draft.scheduledAt, props.timeZone),
    props.timeZone,
    locale.value
  );
});
const crmTag = computed(() =>
  t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.CRM_TAG', {
    name: props.draft.title.trim(),
  })
);
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

const blocks = computed(() => [
  {
    key: 'audience',
    step: 1,
    title: t(`${NS}.AUDIENCE`),
    main: props.audience.name,
    detail: t(`${NS}.AUDIENCE_DETAIL`, { count: n(props.reach) }),
  },
  {
    key: 'message',
    step: 2,
    title: t(`${NS}.CHANNEL`),
    main: `${props.channelLabel} · ${props.templateName}`,
    detail: [
      t(`${NS}.CHANNEL_DETAIL`, { inbox: props.inboxName }),
      props.bindingSummary,
    ]
      .filter(Boolean)
      .join(' · '),
  },
]);

const openConfirmation = () => {
  if (!isScheduleValid.value) return;
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
          <p class="m-0 text-sm font-semibold text-n-slate-12">{{ block.main }}</p>
          <p class="m-0 text-xs text-n-slate-11">{{ block.detail }}</p>
        </div>
        <Button
          :label="t(`${NS}.CHANGE`)"
          :aria-label="t(`${NS}.CHANGE_ARIA`, { block: block.title })"
          variant="ghost"
          size="sm"
          class="!min-h-11"
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
      <div class="rounded-xl bg-[#0D2344] p-4 text-white">
        <p class="m-0 text-xs font-semibold uppercase opacity-80">
          {{ t(`${NS}.RECEIVE`) }}
        </p>
        <p class="m-0 text-4xl font-semibold tabular-nums" data-test="receivers">
          {{ n(receivers) }}
        </p>
        <p class="m-0 text-sm opacity-80">
          {{ channelLabel }} · {{ isLater ? whenText : t(`${NS}.NOW`) }}
        </p>
      </div>
      <dl class="m-0 flex flex-col gap-1 text-sm">
        <div class="flex justify-between gap-3">
          <dt class="text-n-slate-11">{{ t(`${NS}.ON_CHANNEL`) }}</dt>
          <dd class="m-0 font-semibold tabular-nums">{{ n(reach) }}</dd>
        </div>
        <div v-if="excluded" class="flex justify-between gap-3">
          <dt class="text-n-slate-11">{{ t(`${NS}.LEFT_OUT`) }}</dt>
          <dd class="m-0 tabular-nums">−{{ n(excluded) }}</dd>
        </div>
      </dl>
      <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <Button
        :label="actionLabel"
        :disabled="!isScheduleValid || !receivers || isSubmitting"
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
