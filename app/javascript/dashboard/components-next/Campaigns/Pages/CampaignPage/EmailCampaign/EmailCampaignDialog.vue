<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  isRecipientImportActive,
  recipientImportError,
} from 'dashboard/helper/emailCampaignImport';

import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  campaign: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved', 'close']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const uiFlags = useMapGetter('emailCampaigns/getUIFlags');
const identities = useMapGetter('emailSenderIdentities/getIdentities');
const allInboxes = useMapGetter('inboxes/getInboxes');

// Webmail gratuito não pode disparar via SES (domínio não é seu), mas PODE disparar
// direto pela própria caixa, em baixo volume + throttle. São opções de envio direto.
const WEBMAIL_DOMAINS = [
  'gmail.com',
  'googlemail.com',
  'hotmail.com',
  'hotmail.com.br',
  'outlook.com',
  'outlook.com.br',
  'live.com',
  'msn.com',
  'yahoo.com',
  'yahoo.com.br',
  'ymail.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'gmx.com',
  'proton.me',
  'protonmail.com',
  'bol.com.br',
  'uol.com.br',
  'terra.com.br',
];
const isWebmail = email =>
  WEBMAIL_DOMAINS.includes((email || '').split('@').pop()?.toLowerCase());

const verifiedIdentities = computed(() =>
  (identities.value || []).filter(identity => identity.status === 'verified')
);
const webmailInboxes = computed(() =>
  (allInboxes.value || []).filter(
    inbox =>
      inbox.channel_type === 'Channel::Email' &&
      inbox.email &&
      isWebmail(inbox.email)
  )
);
// Valor composto: 'ses:<id>' (domínio verificado) ou 'inbox:<id>' (envio direto pela caixa).
const senderOptions = computed(() => [
  ...verifiedIdentities.value.map(identity => ({
    value: `ses:${identity.id}`,
    label: identity.domain,
  })),
  ...webmailInboxes.value.map(inbox => ({
    value: `inbox:${inbox.id}`,
    label: `${inbox.email} · ${t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.DIRECT_OPTION')}`,
  })),
]);
const hasSenderOption = computed(() => senderOptions.value.length > 0);

const savedCampaignId = ref(props.campaign?.id || null);
const isEditing = computed(() =>
  Boolean(props.campaign?.id || savedCampaignId.value)
);

const initialSender = () => {
  if (
    props.campaign?.delivery_mode === 'direct_inbox' &&
    props.campaign?.sender_inbox_id
  ) {
    return `inbox:${props.campaign.sender_inbox_id}`;
  }
  return props.campaign?.sender_identity_id
    ? `ses:${props.campaign.sender_identity_id}`
    : '';
};

const state = reactive({
  name: props.campaign?.name || '',
  sender: initialSender(),
  fromName: props.campaign?.from_name || '',
  fromEmail: props.campaign?.from_email || '',
  preheader: props.campaign?.preheader || '',
  replyTo: props.campaign?.reply_to || '',
});

const isDirectMode = computed(() => state.sender.startsWith('inbox:'));
const selectedInbox = computed(() =>
  webmailInboxes.value.find(inbox => `inbox:${inbox.id}` === state.sender)
);
const selectedIdentity = computed(() =>
  verifiedIdentities.value.find(
    identity => `ses:${identity.id}` === state.sender
  )
);

const baseFileInput = ref(null);
const baseFile = ref(null);

const selectedDomain = computed(() => selectedIdentity.value?.domain);

const errors = reactive({
  name: false,
  sender: false,
  fromName: false,
  fromEmail: false,
  replyTo: false,
});

// Ao escolher uma caixa de envio direto, o "De:" é a própria caixa (campo travado).
const onSenderChange = () => {
  errors.sender = false;
  if (isDirectMode.value && selectedInbox.value) {
    state.fromEmail = selectedInbox.value.email;
    errors.fromEmail = false;
    if (!state.replyTo.trim()) state.replyTo = selectedInbox.value.email;
  }
};

const fromEmailHint = computed(() =>
  selectedDomain.value
    ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_HINT', {
        domain: selectedDomain.value,
      })
    : t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_HINT_NO_DOMAIN')
);

const isImporting = computed(() => uiFlags.value.isImporting);
const isSaving = computed(
  () =>
    uiFlags.value.isCreating || uiFlags.value.isUpdating || isImporting.value
);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// fromEmail must be a valid address AND belong to the selected verified domain
// (mirrors the backend from_email_matches_sender_domain rule) so the user gets
// an inline error instead of a generic 422 on submit.
const fromEmailValid = () => {
  // Envio direto: o "De:" é sempre a própria caixa (sem checagem de domínio SES).
  if (isDirectMode.value) return true;
  const email = state.fromEmail.trim().toLowerCase();
  if (!EMAIL_RE.test(email)) return false;
  const domain = selectedDomain.value?.toLowerCase();
  return !domain || email.endsWith(`@${domain}`);
};

const validate = () => {
  errors.name = state.name.trim().length === 0;
  errors.sender = !state.sender;
  errors.fromName = state.fromName.trim().length === 0;
  errors.fromEmail = !fromEmailValid();
  errors.replyTo = !EMAIL_RE.test(state.replyTo.trim());
  return (
    !errors.name &&
    !errors.sender &&
    !errors.fromName &&
    !errors.fromEmail &&
    !errors.replyTo
  );
};

// Field messages: empty -> "required"; filled-but-invalid -> "invalid"; clean -> hint.
const fromEmailMessage = computed(() => {
  if (!errors.fromEmail) return fromEmailHint.value;
  return state.fromEmail.trim().length === 0
    ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_ERROR')
    : t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_INVALID');
});
const replyToMessage = computed(() => {
  if (!errors.replyTo) return t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_HINT');
  return state.replyTo.trim().length === 0
    ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_ERROR')
    : t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_INVALID');
});

const close = () => emit('close');

const pickBaseFile = () => baseFileInput.value?.click();

const onBaseFileChange = event => {
  baseFile.value = event.target.files?.[0] || null;
};

const importBase = async campaignId => {
  if (!baseFile.value) return;
  try {
    await store.dispatch('emailCampaigns/importRecipients', {
      id: campaignId,
      file: baseFile.value,
    });
    baseFile.value = null;
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.QUEUED'));
  } catch (error) {
    useAlert(recipientImportError(t, error.response?.data?.error));
    throw new Error('base_import_failed');
  }
};

const buildPayload = () => {
  const base = {
    name: state.name.trim(),
    from_name: state.fromName.trim(),
    preheader: state.preheader.trim() || null,
    reply_to: state.replyTo.trim(),
  };
  if (isDirectMode.value) {
    return {
      ...base,
      delivery_mode: 'direct_inbox',
      sender_inbox_id: selectedInbox.value?.id,
      from_email: selectedInbox.value?.email,
    };
  }
  return {
    ...base,
    delivery_mode: 'ses',
    sender_identity_id: selectedIdentity.value?.id,
    from_email: state.fromEmail.trim(),
  };
};

const submit = async ({ openEditor = false } = {}) => {
  if (!validate()) return;

  try {
    let saved;
    if (isEditing.value || savedCampaignId.value) {
      saved = await store.dispatch('emailCampaigns/update', {
        id: props.campaign?.id || savedCampaignId.value,
        ...buildPayload(),
      });
    } else {
      saved = await store.dispatch('emailCampaigns/create', buildPayload());
    }

    const currentCampaignId = saved?.id || savedCampaignId.value;
    savedCampaignId.value = currentCampaignId;

    if (baseFile.value && currentCampaignId) {
      await importBase(currentCampaignId);
    }

    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SUCCESS'));
    emit('saved');

    if (openEditor && currentCampaignId) {
      router.push({
        name: 'campaigns_email_builder',
        params: {
          accountId: route.params.accountId,
          campaignId: currentCampaignId,
        },
      });
    } else {
      close();
    }
  } catch (error) {
    if (error?.message !== 'base_import_failed') {
      useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.ERROR'));
    }
  }
};
</script>

<template>
  <form
    class="absolute z-50 flex max-h-[82vh] w-[min(36rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-alpha-3 shadow-xl backdrop-blur-[100px] ltr:right-0 rtl:left-0 top-10"
    @submit.prevent="submit({ openEditor: true })"
    @click.stop
  >
    <div class="flex flex-col gap-2 p-6 pb-4">
      <h3 class="text-base font-medium leading-6 text-n-slate-12">
        {{
          isEditing
            ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.EDIT_TITLE')
            : t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CREATE_TITLE')
        }}
      </h3>
    </div>

    <div class="flex flex-col gap-5 px-6 pb-5 overflow-y-auto">
      <Input
        v-model="state.name"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_LABEL')"
        :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_PLACEHOLDER')"
        :message="
          errors.name ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_ERROR') : ''
        "
        :message-type="errors.name ? 'error' : 'info'"
        @input="errors.name = false"
      />

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_LABEL') }}
        </label>
        <Select
          v-model="state.sender"
          class="w-full [&>select]:w-full"
          :options="senderOptions"
          :disabled="!hasSenderOption"
          :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_PLACEHOLDER')"
          :error="
            errors.sender
              ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_ERROR')
              : ''
          "
          @update:model-value="onSenderChange"
        />
        <p v-if="errors.sender" class="mb-0 text-xs text-n-ruby-9">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_ERROR') }}
        </p>
        <p v-if="!hasSenderOption" class="mb-0 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NO_VERIFIED_DOMAIN') }}
        </p>

        <div
          v-if="isDirectMode"
          class="mt-1 px-3 py-2 outline outline-1 -outline-offset-1 bg-n-ruby-3 outline-n-ruby-5 text-n-ruby-11 rounded-xl"
        >
          <p class="mb-0 text-sm leading-5">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.DIRECT_WARNING') }}
          </p>
        </div>
      </div>

      <Input
        v-model="state.fromName"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_LABEL')"
        :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_PLACEHOLDER')"
        :message="
          errors.fromName
            ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_ERROR')
            : ''
        "
        :message-type="errors.fromName ? 'error' : 'info'"
        @input="errors.fromName = false"
      />

      <Input
        v-model="state.fromEmail"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_LABEL')"
        :placeholder="
          t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_PLACEHOLDER')
        "
        :disabled="isDirectMode"
        :message="
          isDirectMode
            ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_DIRECT_HINT')
            : fromEmailMessage
        "
        :message-type="errors.fromEmail ? 'error' : 'info'"
        @input="errors.fromEmail = false"
      />

      <Input
        v-model="state.replyTo"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_LABEL')"
        :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_PLACEHOLDER')"
        :message="replyToMessage"
        :message-type="errors.replyTo ? 'error' : 'info'"
        @input="errors.replyTo = false"
      />

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_LABEL') }}
        </label>
        <div class="flex flex-wrap items-center gap-3">
          <input
            ref="baseFileInput"
            type="file"
            accept=".csv,.xlsx"
            class="hidden"
            @change="onBaseFileChange"
          />
          <Button
            type="button"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_PICK')"
            icon="i-lucide-upload"
            color="slate"
            variant="outline"
            size="sm"
            :disabled="isSaving || isRecipientImportActive(campaign)"
            @click="pickBaseFile"
          />
          <span v-if="baseFile" class="text-xs truncate text-n-slate-11">
            {{
              t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_SELECTED', {
                name: baseFile.name,
              })
            }}
          </span>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_HINT') }}
        </p>
        <p v-if="isImporting" class="mb-0 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_IMPORTING') }}
        </p>
      </div>
    </div>

    <div
      class="flex items-center justify-between w-full gap-3 p-6 pt-4 border-t border-n-weak bg-n-alpha-2"
    >
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CANCEL')"
        class="w-full"
        :disabled="isSaving"
        @click="close"
      />
      <Button
        type="button"
        color="slate"
        variant="outline"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SAVE_DRAFT')"
        class="w-full"
        :is-loading="isSaving"
        :disabled="isSaving"
        @click="submit({ openEditor: false })"
      />
      <Button
        type="submit"
        color="blue"
        icon="i-lucide-layout-template"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CREATE_AND_OPEN')"
        class="w-full"
        :is-loading="isSaving"
        :disabled="isSaving"
      />
    </div>
  </form>
</template>
