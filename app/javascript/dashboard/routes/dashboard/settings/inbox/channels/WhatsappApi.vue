<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useVuelidate } from '@vuelidate/core';
import { required, helpers } from '@vuelidate/validators';
import WahaInboxAPI from 'dashboard/api/wahaInbox';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = key => t(`INBOX_MGMT.ADD.WHATSAPP_API.${key}`);

const isAiAgent = ref(false);
const channelName = ref('');
const phone = ref('');
const isCreating = ref(false);

const phoneFormat = helpers.regex(/^55\d{11}$/);
const rules = computed(() => ({
  phone: { required, phoneFormat },
  channelName: isAiAgent.value ? {} : { required },
}));
const v$ = useVuelidate(rules, { phone, channelName });

const errorMessageFor = code => {
  const known = {
    invalid_phone: 'INVALID_PHONE',
    integration_not_configured: 'NOT_CONFIGURED',
    account_token_missing: 'NOT_CONFIGURED',
    phone_in_use_elsewhere: 'PHONE_IN_USE_ELSEWHERE',
    phone_connected_elsewhere: 'PHONE_CONNECTED_ELSEWHERE',
    engine_unavailable: 'ENGINE_UNAVAILABLE',
  };
  const key = known[code];
  return key ? tk(`ERROR.${key}`) : tk('ERROR.GENERIC');
};

const createChannel = async () => {
  if (isCreating.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) return;

  isCreating.value = true;
  try {
    const { data } = await WahaInboxAPI.create({
      phone: phone.value.trim(),
      name: isAiAgent.value ? phone.value.trim() : channelName.value.trim(),
      aiAgent: isAiAgent.value,
    });
    await store.dispatch('inboxes/get');
    router.replace({
      name: 'settings_inbox_finish',
      params: { page: 'new', inbox_id: data.id },
    });
  } catch (error) {
    useAlert(errorMessageFor(error?.response?.data?.error));
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader :header-title="tk('TITLE')" :header-content="tk('DESC')" />
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel">
      <div class="flex-shrink-0 flex-grow-0 w-full mb-4">
        <label class="block mb-1 text-sm font-medium">{{
          tk('MODE.LABEL')
        }}</label>
        <div class="flex gap-2">
          <button
            type="button"
            class="flex-1 flex items-center justify-center gap-2 px-3 py-2 text-sm rounded-lg border"
            :class="
              !isAiAgent
                ? 'border-n-brand bg-n-alpha-2 text-n-slate-12'
                : 'border-n-weak text-n-slate-11'
            "
            @click="isAiAgent = false"
          >
            <span class="i-lucide-user size-4" />
            {{ tk('MODE.HUMAN') }}
          </button>
          <button
            type="button"
            class="flex-1 flex items-center justify-center gap-2 px-3 py-2 text-sm rounded-lg border"
            :class="
              isAiAgent
                ? 'border-n-brand bg-n-alpha-2 text-n-slate-12'
                : 'border-n-weak text-n-slate-11'
            "
            @click="isAiAgent = true"
          >
            <span class="i-lucide-bot size-4" />
            {{ tk('MODE.AI') }}
          </button>
        </div>
        <p class="mt-1 text-xs text-n-slate-11">{{ tk('MODE.HINT') }}</p>
      </div>

      <div v-if="!isAiAgent" class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.channelName.$error }">
          {{ tk('CHANNEL_NAME.LABEL') }}
          <input
            v-model="channelName"
            type="text"
            :placeholder="tk('CHANNEL_NAME.PLACEHOLDER')"
            @blur="v$.channelName.$touch"
          />
          <span v-if="v$.channelName.$error" class="message">
            {{ tk('CHANNEL_NAME.ERROR') }}
          </span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.phone.$error }">
          {{ tk('PHONE.LABEL') }}
          <input
            v-model="phone"
            type="text"
            inputmode="numeric"
            :placeholder="tk('PHONE.PLACEHOLDER')"
            @blur="v$.phone.$touch"
          />
        </label>
        <p class="help-text">{{ tk('PHONE.SUBTITLE') }}</p>
        <span v-if="v$.phone.$error" class="text-xs text-n-ruby-11">
          {{ tk('PHONE.ERROR') }}
        </span>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="isCreating"
          :disabled="isCreating"
          type="submit"
          solid
          blue
          :label="tk('SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
