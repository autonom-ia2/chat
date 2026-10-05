<script setup>
import { formatNumber } from 'dashboard/components-next/CampaignJourney/localeTag';
import { PLUS } from 'dashboard/components-next/CampaignJourney/textMarks';
// Passo 2 — SMS (#993 front of #1004, PRD §6.3 SMS, M3): SMS inbox, short text with contact and
// audience fields, characters/parts counter (same rules as the server, smsSegments.js) and the
// preview as an SMS. A person without a value for a field and without a default text is left out.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  CONTACT_TOKENS,
  audienceColumnTokens,
  insertToken,
  renderTokens,
} from './audienceTokens';
import { smsStats } from './smsSegments';

const props = defineProps({
  draft: { type: Object, required: true },
  inboxOptions: { type: Array, default: () => [] },
  extraColumns: { type: Array, default: () => [] },
  sample: { type: Object, default: null },
  preview: { type: Object, default: null },
});

const emit = defineEmits(['update']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.SMS';
const API = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.API';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const textarea = ref(null);

const tokenButtons = computed(() => [
  ...CONTACT_TOKENS.map(item => ({
    token: item.token,
    label: t(`${API}.TOKENS.${item.labelKey}`),
  })),
  ...audienceColumnTokens(props.extraColumns).map(item => ({
    token: item.token,
    label: item.header,
  })),
]);
const labelOf = token =>
  tokenButtons.value.find(item => item.token === token)?.label || token;
const stats = computed(() => smsStats(props.draft.messageBody));
const previewText = computed(() =>
  renderTokens(props.draft.messageBody, {
    sample: props.sample,
    extraColumns: props.extraColumns,
    defaults: props.draft.defaults || {},
    placeholder: token => `[${labelOf(token)}]`,
  })
);
const usedTokens = computed(() =>
  tokenButtons.value
    .map(item => item.token)
    .filter(token => (props.draft.messageBody || '').includes(`{{${token}}}`))
    .filter(token => !['contact.name', 'contact.first_name'].includes(token))
);
const missingCount = computed(
  () => Number(props.preview?.reasons?.missing_variables) || 0
);
const missingFields = computed(() =>
  Object.keys(props.preview?.missing_by_variable || {}).map(key =>
    key === 'empresa' ? labelOf('contact.company') : labelOf(`publico.${key}`)
  )
);

const insert = token => {
  const body = props.draft.messageBody || '';
  const position = textarea.value?.selectionStart ?? body.length;
  emit('update', { messageBody: insertToken(body, token, position) });
};
const setDefault = (token, value) =>
  emit('update', { defaults: { ...props.draft.defaults, [token]: value } });
</script>

<template>
  <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
    <section class="flex min-w-0 flex-col gap-5" data-test="sms-form">
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.INBOX_LABEL`) }}
        </span>
        <ChoiceSelect
          :model-value="draft.inboxId ?? ''"
          :options="inboxOptions"
          :aria-label="t(`${NS}.INBOX_LABEL`)"
          :placeholder="t(`${NS}.INBOX_PLACEHOLDER`)"
          data-test="sms-inbox-choice"
          @update:model-value="inboxId => emit('update', { inboxId })"
        />
        <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.INBOX_HINT`) }}</p>
      </div>
      <div class="flex flex-col gap-2">
        <label
          for="journey-sms-message"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.MESSAGE_LABEL`) }}
        </label>
        <textarea
          id="journey-sms-message"
          ref="textarea"
          :value="draft.messageBody"
          rows="4"
          :placeholder="t(`${NS}.MESSAGE_PLACEHOLDER`)"
          class="m-0 w-full rounded-xl border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          data-test="sms-message"
          @input="event => emit('update', { messageBody: event.target.value })"
        />
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs text-n-slate-11">{{
              t(`${API}.INSERT`)
            }}</span>
            <button
              v-for="item in tokenButtons"
              :key="item.token"
              type="button"
              class="min-h-11 rounded-xl border border-n-weak px-3 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-label="t(`${API}.INSERT_ARIA`, { field: item.label })"
              :data-sms-token="item.token"
              @click="insert(item.token)"
            >
              {{ PLUS }} {{ item.label }}
            </button>
          </div>
          <p
            class="m-0 text-xs text-n-slate-11"
            data-test="sms-counter"
            aria-live="polite"
          >
            {{
              t(
                `${NS}.COUNTER`,
                {
                  characters: n(stats.characters),
                  segments: n(stats.segments),
                },
                stats.segments
              )
            }}
          </p>
        </div>
        <p class="m-0 text-xs text-n-slate-11">
          {{
            t(`${NS}.COUNTER_HINT`, {
              per: stats.per_segment,
              encoding: stats.encoding,
            })
          }}
        </p>
      </div>
      <div
        v-if="preview"
        class="flex flex-col gap-3 rounded-xl px-4 py-3"
        :class="missingCount ? 'bg-n-amber-2' : 'bg-n-teal-2'"
        role="status"
        data-test="sms-coverage"
      >
        <p class="m-0 text-sm text-n-slate-12">
          {{
            missingCount
              ? t(
                  `${API}.MISSING`,
                  { count: n(missingCount), fields: missingFields.join(', ') },
                  missingCount
                )
              : t(`${API}.ALL_IN`)
          }}
        </p>
        <Input
          v-for="token in usedTokens"
          :key="token"
          :model-value="draft.defaults?.[token] || ''"
          :label="t(`${API}.DEFAULT_LABEL`, { field: labelOf(token) })"
          :placeholder="t(`${API}.DEFAULT_PLACEHOLDER`)"
          custom-input-class="!h-11"
          @update:model-value="value => setDefault(token, value)"
        />
      </div>
    </section>
    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4 lg:sticky lg:top-4"
      data-test="sms-preview"
    >
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.PREVIEW_TITLE`) }}
      </h3>
      <div class="rounded-2xl bg-n-solid-1 p-4">
        <p
          v-if="draft.messageBody"
          class="m-0 max-w-xs whitespace-pre-wrap rounded-2xl rounded-tl-sm bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-12"
          data-test="sms-preview-text"
        >
          {{ previewText }}
        </p>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.PREVIEW_EMPTY`) }}
        </p>
      </div>
      <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.PREVIEW_HINT`) }}</p>
    </aside>
  </div>
</template>
