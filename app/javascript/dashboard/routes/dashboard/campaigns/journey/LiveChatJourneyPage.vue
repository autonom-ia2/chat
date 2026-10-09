<script setup>
import { DOT } from 'dashboard/components-next/CampaignJourney/textMarks';
// Chat ao vivo (#993 / #1008, PRD §6.8, D16, M5): an automatic message on the website, without a
// list of people. Its own flow: Quando aparece → Mensagem → Ativar, on Chatwoot's ongoing
// campaigns (campaigns API, same fields as LiveChatCampaignForm). Edit (`:campaignId`) changes
// it, pauses it or turns it on again. Whoever talks gets the mark "campaign_live_chat".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LabeledSwitch from 'dashboard/components-next/switch/LabeledSwitch.vue';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import {
  BOT_SENDER,
  emptyLiveChat,
  fromCampaign,
  isValidPageUrl,
  toCampaignPayload,
} from 'dashboard/components-next/CampaignJourney/liveChatCampaign';

const NS = 'CAMPAIGN_JOURNEY.LIVE_CHAT';
const STEPS = ['WHEN', 'MESSAGE', 'ACTIVATE'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const websiteInboxes = useMapGetter('inboxes/getWebsiteInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');

const form = ref(emptyLiveChat());
const step = ref(1);
const senders = ref([]);
const isSaving = ref(false);
const notFound = ref(false);

const campaignId = computed(() => Number(route.params.campaignId) || null);
const isEdit = computed(() => Boolean(campaignId.value));
const inboxOptions = computed(() =>
  (websiteInboxes.value || []).map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);
const senderOptions = computed(() => [
  { value: BOT_SENDER, label: t(`${NS}.SENDER_BOT`) },
  ...senders.value.map(agent => ({ value: agent.id, label: agent.name })),
]);
const urlValid = computed(() => isValidPageUrl(form.value.url));
const whenReady = computed(
  () =>
    Boolean(form.value.inboxId) &&
    urlValid.value &&
    Number(form.value.timeOnPage) >= 0
);
const messageReady = computed(
  () => Boolean(form.value.title.trim()) && Boolean(form.value.message.trim())
);
const crmTag = computed(() =>
  t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.CRM_TAG', {
    name: form.value.title.trim() || '…',
  })
);

const update = patch => {
  form.value = { ...form.value, ...patch };
};

const loadSenders = async inboxId => {
  senders.value = [];
  if (!inboxId) return;
  try {
    const response = await store.dispatch('inboxMembers/get', { inboxId });
    senders.value = response?.data?.payload ?? [];
  } catch {
    senders.value = [];
  }
};

const chooseInbox = inboxId => {
  update({ inboxId, senderId: BOT_SENDER });
  loadSenders(inboxId);
};

const save = async (patch = {}) => {
  isSaving.value = true;
  const payload = toCampaignPayload({ ...form.value, ...patch });
  try {
    if (isEdit.value) {
      await store.dispatch('campaigns/update', {
        id: campaignId.value,
        ...payload,
      });
      update(patch);
      useAlert(t(`${NS}.SAVED`));
    } else {
      await store.dispatch('campaigns/create', payload);
      useAlert(t(`${NS}.CREATED`));
      router.push({
        name: 'campaigns_journey_index',
        query: { channel: 'live_chat' },
      });
    }
  } catch {
    useAlert(t(`${NS}.ERROR`));
  } finally {
    isSaving.value = false;
  }
};

const cancel = () =>
  router.push({
    name: 'campaigns_journey_index',
    query: { channel: 'live_chat' },
  });

useOnEnter(async () => {
  step.value = 1;
  notFound.value = false;
  form.value = emptyLiveChat();
  await Promise.allSettled([
    store.dispatch('inboxes/get'),
    store.dispatch('campaigns/get'),
  ]);
  if (!isEdit.value) return;
  const campaign = (campaigns.value || []).find(
    item => item.id === campaignId.value
  );
  if (!campaign) {
    notFound.value = true;
    return;
  }
  form.value = fromCampaign(campaign);
  loadSenders(form.value.inboxId);
});
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[64rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t('CAMPAIGN_JOURNEY.LIST.BREADCRUMB')"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <router-link
          :to="{ name: 'campaigns_journey_index' }"
          class="text-n-slate-11 hover:underline"
        >
          {{ t('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS') }}
        </router-link>
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ isEdit ? t(`${NS}.EDIT_TITLE`) : t(`${NS}.TITLE`) }}
        </span>
      </nav>
      <header class="mb-5 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1
            class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ isEdit ? t(`${NS}.EDIT_TITLE`) : t(`${NS}.TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm text-n-slate-11">
            {{ t(`${NS}.SUBTITLE`) }}
          </p>
        </div>
        <span
          v-if="isEdit && !notFound"
          class="rounded-full px-3 py-1 text-xs font-semibold"
          :class="
            form.enabled
              ? 'bg-n-blue-3 text-n-blue-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          data-test="live-chat-status"
        >
          {{ form.enabled ? t(`${NS}.ALWAYS_ON`) : t(`${NS}.PAUSED`) }}
        </span>
      </header>

      <p
        v-if="notFound"
        role="alert"
        class="rounded-2xl border border-n-ruby-6 bg-n-solid-1 p-4 text-sm text-n-ruby-11"
      >
        {{ t(`${NS}.NOT_FOUND`) }}
      </p>

      <template v-else>
        <nav
          :aria-label="t(`${NS}.STEPS.LABEL`)"
          class="mb-5 rounded-2xl border border-n-weak bg-n-solid-1 px-3 py-2 shadow-sm"
        >
          <ol class="m-0 flex list-none flex-wrap items-center gap-1 p-0">
            <li v-for="(key, index) in STEPS" :key="key">
              <button
                type="button"
                class="flex min-h-11 items-center gap-2 rounded-xl px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-60"
                :class="
                  step === index + 1
                    ? 'bg-n-blue-3 font-semibold text-n-blue-11'
                    : 'text-n-slate-11'
                "
                :aria-current="step === index + 1 ? 'step' : undefined"
                :disabled="
                  index + 1 > step &&
                  !(
                    isEdit ||
                    (index === 1 && whenReady) ||
                    (index === 2 && whenReady && messageReady)
                  )
                "
                :data-live-step="index + 1"
                @click="step = index + 1"
              >
                <span
                  class="flex size-6 items-center justify-center rounded-full bg-n-alpha-2 text-xs"
                  aria-hidden="true"
                >
                  {{ index + 1 }}
                </span>
                {{ t(`${NS}.STEPS.${key}`) }}
              </button>
            </li>
          </ol>
        </nav>

        <section
          v-if="step === 1"
          class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
          data-test="live-chat-when"
        >
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`${NS}.INBOX_LABEL`) }}
            </span>
            <ChoiceSelect
              :model-value="form.inboxId ?? ''"
              :options="inboxOptions"
              :aria-label="t(`${NS}.INBOX_LABEL`)"
              :placeholder="t(`${NS}.INBOX_PLACEHOLDER`)"
              @update:model-value="chooseInbox"
            />
          </div>
          <Input
            :model-value="form.url"
            type="url"
            :label="t(`${NS}.URL_LABEL`)"
            :placeholder="t(`${NS}.URL_PLACEHOLDER`)"
            :message="form.url && !urlValid ? t(`${NS}.URL_ERROR`) : ''"
            :message-type="form.url && !urlValid ? 'error' : 'info'"
            custom-input-class="!h-11"
            data-test="live-chat-url"
            @update:model-value="url => update({ url })"
          />
          <Input
            :model-value="form.timeOnPage"
            type="number"
            min="0"
            :label="t(`${NS}.TIME_LABEL`)"
            custom-input-class="!h-11"
            data-test="live-chat-time"
            @update:model-value="
              timeOnPage => update({ timeOnPage: Number(timeOnPage) })
            "
          />
          <div>
            <LabeledSwitch
              :checked="form.businessHours"
              :label="t(`${NS}.BUSINESS_HOURS`)"
              data-test="live-chat-hours"
              @toggle="update({ businessHours: !form.businessHours })"
            />
          </div>
          <div class="flex justify-between gap-3">
            <Button
              :label="t(`${NS}.CANCEL`)"
              variant="outline"
              color="slate"
              class="!min-h-11 !rounded-xl"
              @click="cancel"
            />
            <Button
              :label="t(`${NS}.CONTINUE`)"
              :disabled="!whenReady"
              class="!min-h-11 !rounded-xl"
              data-test="live-chat-next"
              @click="step = 2"
            />
          </div>
        </section>

        <div
          v-else-if="step === 2"
          class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start"
        >
          <section
            class="flex min-w-0 flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
            data-test="live-chat-message"
          >
            <div class="flex flex-col gap-2">
              <Input
                :model-value="form.title"
                :label="t(`${NS}.NAME_LABEL`)"
                :placeholder="t(`${NS}.NAME_PLACEHOLDER`)"
                custom-input-class="!h-11"
                data-test="live-chat-title"
                @update:model-value="title => update({ title })"
              />
              <p class="m-0 text-xs text-n-slate-11">
                {{ t(`${NS}.CRM_NOTE`, { tag: crmTag }) }}
              </p>
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t(`${NS}.SENDER_LABEL`) }}
              </span>
              <ChoiceSelect
                :model-value="form.senderId"
                :options="senderOptions"
                :aria-label="t(`${NS}.SENDER_LABEL`)"
                @update:model-value="senderId => update({ senderId })"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label
                for="journey-live-chat-text"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ t(`${NS}.TEXT_LABEL`) }}
              </label>
              <textarea
                id="journey-live-chat-text"
                :value="form.message"
                rows="4"
                :placeholder="t(`${NS}.TEXT_PLACEHOLDER`)"
                class="m-0 w-full rounded-xl border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                data-test="live-chat-text"
                @input="event => update({ message: event.target.value })"
              />
            </div>
            <div class="flex justify-between gap-3">
              <Button
                :label="t(`${NS}.BACK`)"
                variant="outline"
                color="slate"
                class="!min-h-11 !rounded-xl"
                @click="step = 1"
              />
              <Button
                :label="t(`${NS}.CONTINUE`)"
                :disabled="!messageReady"
                class="!min-h-11 !rounded-xl"
                data-test="live-chat-next-2"
                @click="step = 3"
              />
            </div>
          </section>
          <aside
            class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
            data-test="live-chat-preview"
          >
            <h2 class="m-0 text-sm font-medium text-n-slate-12">
              {{ t(`${NS}.PREVIEW`) }}
            </h2>
            <div
              class="flex flex-col items-end gap-2 rounded-2xl bg-n-solid-1 p-4"
            >
              <p
                class="m-0 max-w-xs whitespace-pre-wrap rounded-2xl rounded-br-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
              >
                {{ form.message || t(`${NS}.PREVIEW_EMPTY`) }}
              </p>
              <span
                class="flex size-11 items-center justify-center rounded-full bg-n-blue-9 text-white"
                aria-hidden="true"
              >
                <span class="i-lucide-message-circle size-5" />
              </span>
            </div>
          </aside>
        </div>

        <section
          v-else
          class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
          data-test="live-chat-activate"
        >
          <p class="m-0 text-sm font-semibold text-n-slate-12">
            {{ form.title }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{
              t(`${NS}.SUMMARY_WHEN`, {
                url: form.url,
                seconds: form.timeOnPage,
              })
            }}
            <template v-if="form.businessHours">
              {{ DOT }} {{ t(`${NS}.SUMMARY_HOURS`) }}
            </template>
          </p>
          <p class="m-0 whitespace-pre-wrap text-sm text-n-slate-12">
            {{ form.message }}
          </p>
          <p class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.CRM_NOTE`, { tag: crmTag }) }}
          </p>
          <div class="flex flex-wrap justify-between gap-3">
            <Button
              :label="t(`${NS}.BACK`)"
              variant="outline"
              color="slate"
              class="!min-h-11 !rounded-xl"
              @click="step = 2"
            />
            <div class="flex flex-wrap gap-2">
              <Button
                v-if="isEdit"
                :label="form.enabled ? t(`${NS}.PAUSE`) : t(`${NS}.RESUME`)"
                variant="outline"
                color="slate"
                class="!min-h-11 !rounded-xl"
                :is-loading="isSaving"
                data-test="live-chat-toggle"
                @click="save({ enabled: !form.enabled })"
              />
              <Button
                :label="isEdit ? t(`${NS}.SAVE`) : t(`${NS}.ACTIVATE`)"
                :disabled="!whenReady || !messageReady || isSaving"
                :is-loading="isSaving"
                class="!min-h-11 !rounded-xl"
                data-test="live-chat-save"
                @click="save(isEdit ? {} : { enabled: true })"
              />
            </div>
          </div>
        </section>
      </template>
    </div>
  </section>
</template>
