<script setup>
// Passo 2 — E-mail (#993 front of #999, PRD §6.3 E-mail, D9–D13; api-999.md §2.3). First the
// sender (verified domain or webmail inbox for direct send) and the inbox for replies; then
// POST campaign_journey/campaigns creates the draft linked to the audience and the existing
// editor (EmailBuilderPage: "Como você quer começar?", AI, library, blocks, details) opens
// unchanged. Back here (?email=<id>, #1093) the page reads the e-mail again, so the content
// summary shows and the journey goes on to Revisar.
import { computed, ref } from 'vue';
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

const emit = defineEmits(['update', 'create', 'openEditor', 'manageIdentity']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.EMAIL';
const { t } = useI18n();

const senderOptions = computed(() => [
  ...props.identities.filter(isVerifiedIdentity).map(identity => ({
    value: `identity:${identity.id}`,
    label: t(`${NS}.SENDER_DOMAIN`, { domain: identity.domain }),
  })),
  ...props.inboxes.filter(isDirectSendInbox).map(inbox => ({
    value: `inbox:${inbox.id}`,
    label: t(`${NS}.SENDER_INBOX`, { email: inbox.email }),
  })),
]);
// #2237: the domain is the sender and the address is chosen per campaign. With no reply inbox
// chosen, replies go to the domain's default inbox when it has one, otherwise to the campaign
// From (EmailCampaigns::ReplyTo); the empty option says which.
const selectedIdentity = computed(() => {
  const [kind, id] = String(props.draft.emailSender || '').split(':');
  const identityId =
    kind === 'identity' ? id : props.emailCampaign?.sender_identity_id;
  return identityId
    ? props.identities.find(item => String(item.id) === String(identityId))
    : null;
});
const senderDomain = computed(() => selectedIdentity.value?.domain || '');
const defaultReplyLabel = computed(() => {
  const inboxId = selectedIdentity.value?.reply_to_inbox_id;
  const inbox = inboxId && props.inboxes.find(item => item.id === inboxId);
  return inbox
    ? t(`${NS}.REPLY_DOMAIN_DEFAULT`, { name: inbox.name })
    : t(`${NS}.REPLY_NONE`);
});
const isDomain = computed(() =>
  String(props.draft.emailSender || '').startsWith('identity:')
);
const emailInboxes = computed(() =>
  props.inboxes.filter(
    inbox => inbox.channel_type === 'Channel::Email' && inbox.email
  )
);
const normalized = address =>
  String(address || '')
    .trim()
    .toLowerCase();
// #2237 (decision A): replies should land in the platform. For a domain sender the journey
// suggests the domain's reply inbox or an e-mail inbox of the same domain — visible and
// changeable — instead of leaving replies on whoever's address sends.
const suggestedReplyInbox = identity => {
  if (!identity) return null;
  return (
    emailInboxes.value.find(inbox => inbox.id === identity.reply_to_inbox_id) ||
    emailInboxes.value.find(inbox =>
      inbox.email.toLowerCase().endsWith(`@${identity.domain}`.toLowerCase())
    ) ||
    null
  );
};
// With "same as the sender" and no domain inbox, replies go to the From itself; say so when
// that address is not an inbox here, because those replies never reach the platform.
const replyOutsideAddress = computed(() => {
  const domainInboxId = selectedIdentity.value?.reply_to_inbox_id;
  const domainInboxHere =
    domainInboxId &&
    emailInboxes.value.some(inbox => inbox.id === domainInboxId);
  if (props.draft.replyInboxId || domainInboxHere) return '';
  const from = String(props.draft.fromEmail || '').trim();
  if (!isDomain.value || !from) return '';
  return emailInboxes.value.some(
    inbox => normalized(inbox.email) === normalized(from)
  )
    ? ''
    : from;
});
const replyOptions = computed(() => [
  { value: '', label: defaultReplyLabel.value },
  ...emailInboxes.value.map(inbox => ({
    value: inbox.id,
    label: `${inbox.name} · ${inbox.email}`,
  })),
]);
const replyInbox = computed(() =>
  props.inboxes.find(
    inbox => inbox.id === props.emailCampaign?.reply_to_inbox_id
  )
);
const canCreate = computed(
  () =>
    Boolean(props.draft.title.trim()) &&
    Boolean(props.draft.emailSender) &&
    (!isDomain.value || Boolean(String(props.draft.fromEmail || '').trim()))
);

// The reply inbox is a suggestion until the person picks one themselves; while it is, each
// change of sender recomputes it, so a suggestion made for one domain never sticks to another.
const replyTouched = ref(false);
const chooseReply = replyInboxId => {
  replyTouched.value = true;
  emit('update', { replyInboxId });
};

const chooseSender = value => {
  const [kind, id] = String(value).split(':');
  const identity =
    kind === 'identity'
      ? props.identities.find(item => String(item.id) === id)
      : null;
  const keepReply = replyTouched.value;
  if (!identity) {
    emit('update', {
      emailSender: value,
      fromEmail: '',
      ...(keepReply ? {} : { replyInboxId: '' }),
    });
    return;
  }
  // The domain's saved address belongs to whoever registered it (#2237), so it is never filled
  // in for you: the field starts with the suggested inbox's address when it is of this domain,
  // or empty for you to type.
  const inbox = suggestedReplyInbox(identity);
  const inboxFrom =
    inbox &&
    inbox.email.toLowerCase().endsWith(`@${identity.domain}`.toLowerCase())
      ? inbox.email
      : '';
  emit('update', {
    emailSender: value,
    fromEmail: inboxFrom,
    ...(keepReply ? {} : { replyInboxId: inbox ? inbox.id : '' }),
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
        :message="t(`${NS}.FROM_EMAIL_HINT`, { domain: senderDomain })"
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
          @update:model-value="chooseReply"
        />
        <p
          v-if="replyOutsideAddress"
          class="m-0 text-xs text-n-amber-11"
          data-test="email-reply-outside"
        >
          {{ t(`${NS}.REPLY_OUTSIDE`, { email: replyOutsideAddress }) }}
        </p>
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
          {{
            replyInbox
              ? replyInbox.name
              : emailCampaign.reply_to_address || defaultReplyLabel
          }}
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
      </div>
    </div>
  </section>
</template>
