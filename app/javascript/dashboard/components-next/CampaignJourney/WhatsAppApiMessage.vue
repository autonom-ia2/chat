<script setup>
import { formatNumber } from 'dashboard/components-next/CampaignJourney/localeTag';
import { DOT, PLUS } from 'dashboard/components-next/CampaignJourney/textMarks';
// Passo 2 — WhatsApp API (#993 front of #999, PRD §6.3, D7; api-999.md §2.2). Inbox marked for
// campaigns, free text with contact and audience fields ({{contact.first_name}},
// {{publico.<key>}}), "Usar modelo salvo", optional attachment and the automatic pace notice.
// A person without a value for a field and without a default text is left out ("falta …").
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  CONTACT_TOKENS,
  audienceColumnTokens,
  insertToken,
} from './audienceTokens';

const props = defineProps({
  draft: { type: Object, required: true },
  inboxOptions: { type: Array, default: () => [] },
  // [{ id, name, body }] saved templates of the chosen inbox
  templates: { type: Array, default: () => [] },
  extraColumns: { type: Array, default: () => [] },
  mediaFile: { type: Object, default: null },
  // recipient preview { missing_by_variable: { 'publico.vencimento': 2, ... }, reasons }
  preview: { type: Object, default: null },
});

const emit = defineEmits(['update', 'attach']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.API';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const textarea = ref(null);
const fileInput = ref(null);

const columnTokens = computed(() => audienceColumnTokens(props.extraColumns));
const tokenButtons = computed(() => [
  ...CONTACT_TOKENS.map(item => ({
    token: item.token,
    label: t(`${NS}.TOKENS.${item.labelKey}`),
  })),
  ...columnTokens.value.map(item => ({
    token: item.token,
    label: item.header,
  })),
]);
const templateOptions = computed(() =>
  props.templates.map(template => ({
    value: template.id,
    label: template.name,
  }))
);
const labelOf = token =>
  tokenButtons.value.find(item => item.token === token)?.label || token;

// Fields used in the message, in order (contact.name / first_name never miss).
const usedTokens = computed(() => {
  const body = props.draft.messageBody || '';
  return tokenButtons.value
    .map(item => item.token)
    .filter(token => body.includes(`{{${token}}}`))
    .filter(token => !['contact.name', 'contact.first_name'].includes(token));
});
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

const chooseTemplate = id => {
  const template = props.templates.find(item => item.id === id);
  emit('update', {
    apiTemplateId: id,
    messageBody: template?.body ?? props.draft.messageBody,
  });
};

const setDefault = (token, value) =>
  emit('update', { defaults: { ...props.draft.defaults, [token]: value } });

const pickFile = () => fileInput.value?.click();
const onFile = () => emit('attach', fileInput.value?.files?.[0] || null);
</script>

<template>
  <section class="flex flex-col gap-5" data-test="api-form">
    <div class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.INBOX_LABEL`) }}
      </span>
      <ChoiceSelect
        :model-value="draft.inboxId ?? ''"
        :options="inboxOptions"
        :aria-label="t(`${NS}.INBOX_LABEL`)"
        :placeholder="t(`${NS}.INBOX_PLACEHOLDER`)"
        data-test="api-inbox-choice"
        @update:model-value="
          inboxId => emit('update', { inboxId, apiTemplateId: null })
        "
      />
      <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.INBOX_HINT`) }}</p>
    </div>
    <div v-if="draft.inboxId" class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.TEMPLATE_LABEL`) }}
      </span>
      <ChoiceSelect
        v-if="templateOptions.length"
        :model-value="draft.apiTemplateId ?? ''"
        :options="templateOptions"
        :aria-label="t(`${NS}.TEMPLATE_LABEL`)"
        :placeholder="t(`${NS}.TEMPLATE_PLACEHOLDER`)"
        data-test="api-template-choice"
        @update:model-value="chooseTemplate"
      />
      <p v-else class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.TEMPLATE_NONE`) }}
      </p>
    </div>
    <div class="flex flex-col gap-2">
      <label
        for="journey-api-message"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t(`${NS}.MESSAGE_LABEL`) }}
      </label>
      <textarea
        id="journey-api-message"
        ref="textarea"
        :value="draft.messageBody"
        rows="5"
        :placeholder="t(`${NS}.MESSAGE_PLACEHOLDER`)"
        class="m-0 w-full rounded-xl border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        data-test="api-message"
        @input="event => emit('update', { messageBody: event.target.value })"
      />
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs text-n-slate-11">{{ t(`${NS}.INSERT`) }}</span>
        <button
          v-for="item in tokenButtons"
          :key="item.token"
          type="button"
          class="min-h-11 rounded-xl border border-n-weak px-3 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :aria-label="t(`${NS}.INSERT_ARIA`, { field: item.label })"
          :data-token="item.token"
          @click="insert(item.token)"
        >
          {{ PLUS }} {{ item.label }}
        </button>
      </div>
    </div>
    <div
      v-if="preview"
      class="flex flex-col gap-3 rounded-xl px-4 py-3"
      :class="missingCount ? 'bg-n-amber-2' : 'bg-n-teal-2'"
      role="status"
      data-test="api-coverage"
    >
      <p class="m-0 text-sm text-n-slate-12">
        {{
          missingCount
            ? t(
                `${NS}.MISSING`,
                { count: n(missingCount), fields: missingFields.join(', ') },
                missingCount
              )
            : t(`${NS}.ALL_IN`)
        }}
      </p>
      <Input
        v-for="token in usedTokens"
        :key="token"
        :model-value="draft.defaults?.[token] || ''"
        :label="t(`${NS}.DEFAULT_LABEL`, { field: labelOf(token) })"
        :placeholder="t(`${NS}.DEFAULT_PLACEHOLDER`)"
        custom-input-class="!h-11"
        :data-default="token"
        @update:model-value="value => setDefault(token, value)"
      />
    </div>
    <div
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-dashed border-n-slate-7 px-4 py-3"
    >
      <p class="m-0 text-sm">
        <strong class="text-n-slate-12">{{ t(`${NS}.ATTACH`) }}</strong>
        <span class="text-xs text-n-slate-11">
          {{ DOT }}
          {{ mediaFile ? mediaFile.name : t(`${NS}.ATTACH_HINT`) }}
        </span>
      </p>
      <input
        ref="fileInput"
        type="file"
        class="hidden"
        accept="image/*,video/*,application/pdf"
        data-test="api-file"
        @change="onFile"
      />
      <Button
        v-if="!mediaFile"
        :label="t(`${NS}.ATTACH_ACTION`)"
        variant="outline"
        color="slate"
        size="sm"
        class="!min-h-11"
        @click="pickFile"
      />
      <Button
        v-else
        :label="t(`${NS}.ATTACH_REMOVE`)"
        variant="ghost"
        color="ruby"
        size="sm"
        class="!min-h-11"
        @click="emit('attach', null)"
      />
    </div>
    <p class="m-0 rounded-xl bg-n-alpha-1 px-4 py-3 text-xs text-n-slate-11">
      {{ t(`${NS}.PACE`) }}
    </p>
  </section>
</template>
