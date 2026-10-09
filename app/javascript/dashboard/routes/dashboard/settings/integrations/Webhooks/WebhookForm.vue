<script>
import { useVuelidate } from '@vuelidate/core';
import { required, url, minLength } from '@vuelidate/validators';
import wootConstants from 'dashboard/constants/globals';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import { useConfig } from 'dashboard/composables/useConfig';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { EXAMPLE_WEBHOOK_URL } = wootConstants;

const SUPPORTED_WEBHOOK_EVENTS = [
  'conversation_created',
  'conversation_status_changed',
  'conversation_updated',
  'message_created',
  'message_updated',
  'webwidget_triggered',
  'contact_created',
  'contact_updated',
  'conversation_typing_on',
  'conversation_typing_off',
];

// CRM Kanban "Conexões" outgoing webhook events. Canonical dotted strings MUST
// match the backend Webhook::CRM_WEBHOOK_EVENTS (app/models/webhook.rb) exactly,
// since the stored value IS the subscription string the listener filters on.
// Dotted (not underscored) so they cannot collide with the core EVENTS i18n map.
const CRM_WEBHOOK_EVENTS = [
  { value: 'crm.card.created', labelKey: 'CRM_CARD_CREATED' },
  { value: 'crm.card.moved', labelKey: 'CRM_CARD_MOVED' },
  { value: 'crm.card.won', labelKey: 'CRM_CARD_WON' },
  { value: 'crm.card.lost', labelKey: 'CRM_CARD_LOST' },
  { value: 'crm.card.resolved', labelKey: 'CRM_CARD_RESOLVED' },
  { value: 'crm.card.cancelled', labelKey: 'CRM_CARD_CANCELLED' },
  { value: 'crm.card.reopened', labelKey: 'CRM_CARD_REOPENED' },
  { value: 'crm.card.archived', labelKey: 'CRM_CARD_ARCHIVED' },
];

export default {
  components: {
    NextButton,
  },
  props: {
    value: {
      type: Object,
      default: () => ({}),
    },
    isSubmitting: {
      type: Boolean,
      default: false,
    },
    submitLabel: {
      type: String,
      required: true,
    },
  },
  emits: ['submit', 'cancel'],
  setup() {
    return { v$: useVuelidate() };
  },
  validations: {
    url: {
      required,
      minLength: minLength(7),
      url,
    },
    subscriptions: {
      required,
    },
  },
  data() {
    const { inboxEventsEnabled } = useConfig();
    return {
      url: this.value.url || '',
      name: this.value.name || '',
      subscriptions: this.value.subscriptions || [],
      secretVisible: false,
      supportedWebhookEvents: inboxEventsEnabled
        ? [...SUPPORTED_WEBHOOK_EVENTS, 'inbox_updated']
        : SUPPORTED_WEBHOOK_EVENTS,
      crmWebhookEvents: CRM_WEBHOOK_EVENTS,
    };
  },
  computed: {
    hasSecret() {
      return !!this.value.secret;
    },
    isCrmKanbanEnabled() {
      return window.globalConfig?.CRM_KANBAN_ENABLED === 'true';
    },
    webhookURLInputPlaceholder() {
      return this.$t(
        'INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.PLACEHOLDER',
        {
          webhookExampleURL: EXAMPLE_WEBHOOK_URL,
        }
      );
    },
    webhookNameInputPlaceholder() {
      return this.$t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.PLACEHOLDER');
    },
  },
  methods: {
    onSubmit() {
      this.$emit('submit', {
        url: this.url,
        name: this.name,
        subscriptions: this.subscriptions,
      });
    },
    async copySecret() {
      await copyTextToClipboard(this.value.secret);
      useAlert(this.$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.COPY_SUCCESS'));
    },
    getI18nKey,
  },
};
</script>

<template>
  <form class="flex flex-col w-full" @submit.prevent="onSubmit">
    <div class="w-full">
      <label :class="{ error: v$.url.$error }">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.LABEL') }}
        <input
          v-model="url"
          type="text"
          name="url"
          :placeholder="webhookURLInputPlaceholder"
          @input="v$.url.$touch"
        />
        <span v-if="v$.url.$error" class="message">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.ERROR') }}
        </span>
      </label>
      <label>
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.LABEL') }}
        <input
          v-model="name"
          type="text"
          name="name"
          :placeholder="webhookNameInputPlaceholder"
        />
      </label>
      <label v-if="hasSecret" class="mb-4">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.LABEL') }}
        <div class="flex items-center gap-2">
          <input
            :value="
              secretVisible ? value.secret : '••••••••••••••••••••••••••••••••'
            "
            type="text"
            readonly
            class="!mb-0 font-mono"
          />
          <NextButton
            v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.TOGGLE')"
            type="button"
            :icon="secretVisible ? 'i-lucide-eye-off' : 'i-lucide-eye'"
            slate
            faded
            @click="secretVisible = !secretVisible"
          />
          <NextButton
            v-tooltip.top="$t('INTEGRATION_SETTINGS.WEBHOOK.SECRET.COPY')"
            type="button"
            icon="i-lucide-copy"
            slate
            faded
            @click="copySecret"
          />
        </div>
      </label>
      <label :class="{ error: v$.url.$error }" class="mb-2">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.LABEL') }}
      </label>
      <div class="flex flex-col gap-2.5 mb-4">
        <div
          v-for="event in supportedWebhookEvents"
          :key="event"
          class="flex items-center"
        >
          <input
            :id="event"
            v-model="subscriptions"
            type="checkbox"
            :value="event"
            name="subscriptions"
            class="mr-2"
          />
          <label :for="event" class="text-sm">
            {{
              `${$t(
                getI18nKey(
                  'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS',
                  event
                )
              )} (${event})`
            }}
          </label>
        </div>
      </div>

      <template v-if="isCrmKanbanEnabled">
        <label class="mb-2">
          {{
            $t(
              'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.CRM_EVENTS.LABEL'
            )
          }}
        </label>
        <div class="flex flex-col gap-2.5 mb-4">
          <div
            v-for="crmEvent in crmWebhookEvents"
            :key="crmEvent.value"
            class="flex items-center"
          >
            <input
              :id="crmEvent.value"
              v-model="subscriptions"
              type="checkbox"
              :value="crmEvent.value"
              name="subscriptions"
              class="mr-2"
            />
            <label :for="crmEvent.value" class="text-sm">
              {{
                `${$t(
                  `INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.CRM_EVENTS.${crmEvent.labelKey}`
                )} (${crmEvent.value})`
              }}
            </label>
          </div>
        </div>
      </template>
    </div>

    <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
      <NextButton
        faded
        slate
        type="reset"
        :label="$t('INTEGRATION_SETTINGS.WEBHOOK.FORM.CANCEL')"
        @click.prevent="$emit('cancel')"
      />
      <NextButton
        type="submit"
        :disabled="v$.$invalid || isSubmitting"
        :is-loading="isSubmitting"
        :label="submitLabel"
      />
    </div>
  </form>
</template>
