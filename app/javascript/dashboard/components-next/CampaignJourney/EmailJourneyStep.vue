<script setup>
// Passo 2 — E-mail (#993 front of #999, PRD §6.3 E-mail, D9–D13; api-999.md §2.3). First the
// sender (verified domain or webmail inbox for direct send) and the inbox for replies; then
// POST campaign_journey/campaigns creates the draft linked to the audience and the existing
// editor (EmailBuilderPage: "Como você quer começar?", AI, library, blocks, details) opens
// unchanged. Back here, the content summary shows and the journey goes on to Revisar.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { isDirectSendInbox, isVerifiedIdentity } from './emailSenders';
import BrandIdentityLine from 'dashboard/components-next/BrandKits/BrandIdentityLine.vue';

const props = defineProps({
  draft: { type: Object, required: true },
  identities: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  // The e-mail draft once created (GET email_campaigns/campaigns/:id), or null.
  emailCampaign: { type: Object, default: null },
  isCreating: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update',
  'create',
  'openEditor',
  'reload',
  'manageIdentity',
]);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.EMAIL';
const { t } = useI18n();

const senderOptions = computed(() => [
  ...props.identities.filter(isVerifiedIdentity).map(identity => ({
    value: `identity:${identity.id}`,
    label: t(`${NS}.SENDER_DOMAIN`, {
      email: identity.from_email || identity.domain,
    }),
  })),
  ...props.inboxes.filter(isDirectSendInbox).map(inbox => ({
    value: `inbox:${inbox.id}`,
    label: t(`${NS}.SENDER_INBOX`, { email: inbox.email }),
  })),
]);
const replyOptions = computed(() => [
  { value: '', label: t(`${NS}.REPLY_NONE`) },
  ...props.inboxes
    .filter(inbox => inbox.channel_type === 'Channel::Email' && inbox.email)
    .map(inbox => ({
      value: inbox.id,
      label: `${inbox.name} · ${inbox.email}`,
    })),
]);
const replyInbox = computed(() =>
  props.inboxes.find(
    inbox => inbox.id === props.emailCampaign?.reply_to_inbox_id
  )
);
const isDomain = computed(() =>
  String(props.draft.emailSender || '').startsWith('identity:')
);
const canCreate = computed(
  () =>
    Boolean(props.draft.title.trim()) &&
    Boolean(props.draft.emailSender) &&
    (!isDomain.value || Boolean(String(props.draft.fromEmail || '').trim()))
);

const chooseSender = value => {
  const [kind, id] = String(value).split(':');
  const identity =
    kind === 'identity'
      ? props.identities.find(item => String(item.id) === id)
      : null;
  emit('update', {
    emailSender: value,
    fromEmail: identity?.from_email || '',
  });
};
</script>

<template>
  <section class="flex flex-col gap-5" data-test="email-step">
    <template v-if="!draft.emailCampaignId">
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.SENDER_LABEL`) }}
        </span>
        <ChoiceSelect
          :model-value="draft.emailSender || ''"
          :options="senderOptions"
          :aria-label="t(`${NS}.SENDER_LABEL`)"
          :placeholder="t(`${NS}.SENDER_PLACEHOLDER`)"
          data-test="email-sender-choice"
          @update:model-value="chooseSender"
        />
        <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.SENDER_HINT`) }}</p>
      </div>
      <Input
        :model-value="draft.fromName"
        :label="t(`${NS}.FROM_NAME_LABEL`)"
        :placeholder="t(`${NS}.FROM_NAME_PLACEHOLDER`)"
        custom-input-class="!h-11"
        @update:model-value="fromName => emit('update', { fromName })"
      />
      <Input
        v-if="isDomain"
        :model-value="draft.fromEmail"
        type="email"
        :label="t(`${NS}.FROM_EMAIL_LABEL`)"
        custom-input-class="!h-11"
        data-test="email-from"
        @update:model-value="fromEmail => emit('update', { fromEmail })"
      />
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.REPLY_LABEL`) }}
        </span>
        <ChoiceSelect
          :model-value="draft.replyInboxId ?? ''"
          :options="replyOptions"
          :aria-label="t(`${NS}.REPLY_LABEL`)"
          data-test="email-reply-choice"
          @update:model-value="replyInboxId => emit('update', { replyInboxId })"
        />
      </div>
      <BrandIdentityLine
        :kit-id="draft.brandKitId"
        @change="brandKitId => emit('update', { brandKitId })"
        @manage="create => emit('manageIdentity', create)"
      />
      <div class="flex justify-end">
        <Button
          :label="t(`${NS}.CREATE`)"
          :disabled="!canCreate || isCreating"
          :is-loading="isCreating"
          class="!min-h-11 !rounded-xl"
          data-test="email-create"
          @click="emit('create')"
        />
      </div>
    </template>
    <div
      v-else
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
      data-test="email-content"
    >
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.CONTENT_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.CONTENT_HINT`) }}</p>
      <dl
        v-if="emailCampaign"
        class="m-0 grid gap-1 text-sm sm:grid-cols-[10rem_minmax(0,1fr)]"
        data-test="email-details"
      >
        <dt class="text-n-slate-11">{{ t(`${NS}.SENDER_LABEL`) }}</dt>
        <dd class="m-0 break-words text-n-slate-12">
          {{
            [emailCampaign.from_name, emailCampaign.from_email]
              .filter(Boolean)
              .join(' · ')
          }}
        </dd>
        <dt class="text-n-slate-11">{{ t(`${NS}.REPLY_LABEL`) }}</dt>
        <dd class="m-0 truncate text-n-slate-12">
          {{ replyInbox ? replyInbox.name : t(`${NS}.REPLY_NONE`) }}
        </dd>
        <dt v-if="emailCampaign.preheader" class="text-n-slate-11">
          {{ t(`${NS}.PREHEADER_LABEL`) }}
        </dt>
        <dd v-if="emailCampaign.preheader" class="m-0 text-n-slate-12">
          {{ emailCampaign.preheader }}
        </dd>
      </dl>
      <p class="m-0 text-sm text-n-slate-12" data-test="email-subject">
        {{
          emailCampaign?.subject
            ? t(`${NS}.CONTENT_READY`, { subject: emailCampaign.subject })
            : t(`${NS}.CONTENT_EMPTY`)
        }}
      </p>
      <BrandIdentityLine
        :kit-id="draft.brandKitId"
        @change="brandKitId => emit('update', { brandKitId })"
        @manage="create => emit('manageIdentity', create)"
      />
      <div class="flex flex-wrap gap-2">
        <Button
          :label="t(`${NS}.OPEN_EDITOR`)"
          icon="i-lucide-pencil"
          class="!min-h-11 !rounded-xl"
          data-test="email-open-editor"
          @click="emit('openEditor')"
        />
        <Button
          :label="t(`${NS}.RELOAD`)"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          @click="emit('reload')"
        />
      </div>
    </div>
  </section>
</template>
