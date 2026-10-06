<script setup>
// Passo 2 — Mensagem (#993, PRD §6.3, J4, B1, B1b, D1). "Para" with the audience, channel
// cards (connected channels; the ones the audience lacks say why), the campaign name with
// the CRM tag notice and, for WhatsApp Oficial, Cloud inbox, approved template, where
// each variable comes from and the preview. Other channels open their existing forms.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import AudienceChannelBadges from './AudienceChannelBadges.vue';
import TemplateVariableBindings from './TemplateVariableBindings.vue';
import WhatsAppApiMessage from './WhatsAppApiMessage.vue';
import EmailJourneyStep from './EmailJourneyStep.vue';
import SmsJourneyMessage from './SmsJourneyMessage.vue';
import WhatsAppPreview from './WhatsAppPreview.vue';
import {
  CAMPAIGN_CHANNELS,
  CHANNEL_ICONS,
  CHANNEL_LABEL_KEYS,
} from './campaignChannels';
import { channelAvailability } from './audienceChannels';

const props = defineProps({
  audience: { type: Object, required: true },
  channels: { type: Array, default: () => [] },
  draft: { type: Object, required: true },
  inboxOptions: { type: Array, default: () => [] },
  templateOptions: { type: Array, default: () => [] },
  variables: { type: Array, default: () => [] },
  columns: { type: Array, default: () => [] },
  coverage: { type: Object, default: null },
  mediaHeader: { type: Object, default: null },
  previewText: { type: String, default: '' },
  canContinue: { type: Boolean, default: false },
  // WhatsApp API form: { inboxOptions, templates, extraColumns, mediaFile, preview }
  apiForm: { type: Object, default: () => ({}) },
  // E-mail form: { identities, inboxes, emailCampaign, isCreating }
  emailForm: { type: Object, default: () => ({}) },
  // SMS form: { inboxOptions, extraColumns, sample, preview }
  smsForm: { type: Object, default: () => ({}) },
});

const emit = defineEmits([
  'update',
  'bind',
  'default',
  'changeAudience',
  'back',
  'continue',
  'attach',
  'emailCreate',
  'openEditor',
  'emailReload',
]);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE';
const { t } = useI18n();

const HINT_KEYS = {
  [CAMPAIGN_CHANNELS.EMAIL]: 'EMAIL',
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'WHATSAPP_OFFICIAL',
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: 'WHATSAPP_API',
  [CAMPAIGN_CHANNELS.SMS]: 'SMS',
};

// Chat ao vivo has no audience (PRD D16): it is offered in the Público step instead.
const cards = computed(() =>
  props.channels
    .filter(channel => channel !== CAMPAIGN_CHANNELS.LIVE_CHAT)
    .map(channel => ({
      channel,
      ...channelAvailability(channel, props.audience.channels),
    }))
);

// Channels that run inside the journey (#993; SMS since #1004).
const JOURNEY_CHANNELS = [
  CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
  CAMPAIGN_CHANNELS.WHATSAPP_API,
  CAMPAIGN_CHANNELS.EMAIL,
  CAMPAIGN_CHANNELS.SMS,
];
const isJourneyChannel = computed(() =>
  JOURNEY_CHANNELS.includes(props.draft.channel)
);
const isApi = computed(
  () => props.draft.channel === CAMPAIGN_CHANNELS.WHATSAPP_API
);
const isEmail = computed(() => props.draft.channel === CAMPAIGN_CHANNELS.EMAIL);
const isSms = computed(() => props.draft.channel === CAMPAIGN_CHANNELS.SMS);
const isOfficial = computed(
  () => props.draft.channel === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
);
const crmTag = computed(() =>
  t(`${NS}.CRM_TAG`, { name: props.draft.title.trim() || '…' })
);

const cardHint = card =>
  card.available
    ? t(`CAMPAIGN_JOURNEY.CHOOSER.HINTS.${HINT_KEYS[card.channel]}`)
    : t(`${NS}.UNAVAILABLE.${card.reason}`);

const chooseChannel = card => {
  if (!card.available || !JOURNEY_CHANNELS.includes(card.channel)) return;
  emit('update', { channel: card.channel });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-sm"
      data-test="message-audience"
    >
      <div class="flex min-w-0 flex-wrap items-center gap-2">
        <span class="text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.TO`) }}
        </span>
        <strong class="truncate text-sm text-n-slate-12">
          {{ audience.name }}
        </strong>
        <AudienceChannelBadges :badges="audience.badges" />
      </div>
      <Button
        :label="t(`${NS}.CHANGE_AUDIENCE`)"
        variant="ghost"
        size="sm"
        class="!min-h-11"
        data-test="change-audience"
        @click="emit('changeAudience')"
      />
    </section>

    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
    >
      <div>
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${NS}.CHANNELS_TITLE`) }}
        </h2>
        <p class="m-0 mt-1 text-sm text-n-slate-11">
          {{ t(`${NS}.CHANNELS_HINT`) }}
        </p>
      </div>
      <ul class="m-0 grid list-none gap-2 p-0 sm:grid-cols-2 xl:grid-cols-4">
        <li v-for="card in cards" :key="card.channel">
          <button
            type="button"
            class="flex h-full min-h-[5.5rem] w-full items-start gap-3 rounded-xl border px-3 py-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
            :class="
              draft.channel === card.channel
                ? 'border-n-blue-8 bg-n-blue-2'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
            :disabled="!card.available"
            :aria-pressed="draft.channel === card.channel"
            :data-channel-card="card.channel"
            @click="chooseChannel(card)"
          >
            <span
              class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span :class="CHANNEL_ICONS[card.channel]" class="size-5" />
            </span>
            <span class="flex min-w-0 flex-col gap-0.5">
              <strong class="text-sm text-n-slate-12">
                {{
                  t(
                    `CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[card.channel]}`
                  )
                }}
              </strong>
              <span class="text-xs text-n-slate-11" data-test="card-hint">
                {{ cardHint(card) }}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </section>

    <div
      v-if="isJourneyChannel"
      class="grid gap-4 lg:items-start"
      :class="isEmail || isSms ? '' : 'lg:grid-cols-[minmax(0,1fr)_20rem]'"
    >
      <section
        class="flex min-w-0 flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
        :data-test="isOfficial ? 'official-form' : 'channel-form'"
      >
        <div class="flex flex-col gap-2">
          <Input
            :model-value="draft.title"
            :label="t(`${NS}.NAME_LABEL`)"
            :placeholder="t(`${NS}.NAME_PLACEHOLDER`)"
            custom-input-class="!h-11"
            data-test="campaign-title"
            @update:model-value="title => emit('update', { title })"
          />
          <p
            class="m-0 flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
          >
            <span
              class="rounded-full bg-n-blue-3 px-2 py-0.5 font-semibold text-n-blue-11"
            >
              {{ t(`${NS}.CRM_BADGE`) }}
            </span>
            {{ t(`${NS}.CRM_NOTE`, { tag: crmTag }) }}
          </p>
        </div>
        <WhatsAppApiMessage
          v-if="isApi"
          :draft="draft"
          :inbox-options="apiForm.inboxOptions"
          :templates="apiForm.templates"
          :extra-columns="apiForm.extraColumns"
          :media-file="apiForm.mediaFile"
          :preview="apiForm.preview"
          @update="patch => emit('update', patch)"
          @attach="file => emit('attach', file)"
        />
        <SmsJourneyMessage
          v-else-if="isSms"
          :draft="draft"
          :inbox-options="smsForm.inboxOptions"
          :extra-columns="smsForm.extraColumns"
          :sample="smsForm.sample"
          :preview="smsForm.preview"
          @update="patch => emit('update', patch)"
        />
        <EmailJourneyStep
          v-else-if="isEmail"
          :draft="draft"
          :identities="emailForm.identities"
          :inboxes="emailForm.inboxes"
          :email-campaign="emailForm.emailCampaign"
          :is-creating="emailForm.isCreating"
          @update="patch => emit('update', patch)"
          @create="emit('emailCreate')"
          @open-editor="emit('openEditor')"
          @reload="emit('emailReload')"
        />
        <template v-else>
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`${NS}.INBOX_LABEL`) }}
            </span>
            <ChoiceSelect
              :model-value="draft.inboxId ?? ''"
              :options="inboxOptions"
              :aria-label="t(`${NS}.INBOX_LABEL`)"
              :placeholder="t(`${NS}.INBOX_PLACEHOLDER`)"
              data-test="inbox-choice"
              @update:model-value="
                inboxId => emit('update', { inboxId, templateId: null })
              "
            />
            <p class="m-0 text-xs text-n-slate-11">
              {{ t(`${NS}.INBOX_HINT`) }}
            </p>
          </div>
          <div v-if="draft.inboxId" class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`${NS}.TEMPLATE_LABEL`) }}
            </span>
            <ChoiceSelect
              v-if="templateOptions.length"
              :model-value="draft.templateId ?? ''"
              :options="templateOptions"
              :aria-label="t(`${NS}.TEMPLATE_LABEL`)"
              :placeholder="t(`${NS}.TEMPLATE_PLACEHOLDER`)"
              data-test="template-choice"
              @update:model-value="templateId => emit('update', { templateId })"
            />
            <p v-else class="m-0 text-sm text-n-slate-11">
              {{ t(`${NS}.TEMPLATE_EMPTY`) }}
            </p>
          </div>
          <Input
            v-if="mediaHeader"
            :model-value="draft.mediaUrl"
            type="url"
            :label="t(`${NS}.MEDIA_LABEL`)"
            :placeholder="t(`${NS}.MEDIA_PLACEHOLDER`)"
            custom-input-class="!h-11"
            @update:model-value="mediaUrl => emit('update', { mediaUrl })"
          />
          <TemplateVariableBindings
            v-if="variables.length"
            :variables="variables"
            :bindings="draft.bindings"
            :defaults="draft.defaults"
            :columns="columns"
            :coverage="coverage"
            @bind="(key, binding) => emit('bind', key, binding)"
            @default="(key, value) => emit('default', key, value)"
          />
        </template>
      </section>
      <WhatsAppPreview v-if="!isEmail && !isSms" :text="previewText" />
    </div>

    <div class="flex flex-wrap justify-between gap-3">
      <Button
        :label="t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.BACK')"
        variant="outline"
        color="slate"
        class="!min-h-11 !rounded-xl"
        @click="emit('back')"
      />
      <Button
        v-if="
          isOfficial || isApi || isSms || (isEmail && draft.emailCampaignId)
        "
        :label="t(`${NS}.CONTINUE`)"
        :disabled="!canContinue"
        class="!min-h-11 !rounded-xl"
        data-test="continue-review"
        @click="emit('continue')"
      />
    </div>
  </div>
</template>
