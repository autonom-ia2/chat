<script setup>
// Novo público (#993, PRD §6.6, B2, B5, B6, B9, J2, J3, J5, J6, C4–C6). A page, not a modal:
// name + spreadsheet → reading → columns, channels, people, companies → Salvar público.
// Nothing enters the contacts before "Salvar público" (confirm): leaving earlier creates
// nothing (B9). Opened from a campaign draft (`?from=campaign`) it says so and, once
// saved, goes back to the campaign with the new audience selected (J3).
import { computed, onBeforeUnmount, onDeactivated, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AudienceColumns from 'dashboard/components-next/CampaignJourney/AudienceColumns.vue';
import AudienceChannelSwitches from 'dashboard/components-next/CampaignJourney/AudienceChannelSwitches.vue';
import AudiencePeople from 'dashboard/components-next/CampaignJourney/AudiencePeople.vue';
import AudienceCompanies from 'dashboard/components-next/CampaignJourney/AudienceCompanies.vue';
import AudienceChannelBadges from 'dashboard/components-next/CampaignJourney/AudienceChannelBadges.vue';
import { audiencesAPI } from 'dashboard/api/campaignJourney';
import {
  PHASES,
  companiesBlock,
  isRefused,
  phaseOf,
  reasonKey,
  reasonTally,
} from 'dashboard/components-next/CampaignJourney/audienceReview';
import { audienceChannelBadges } from 'dashboard/components-next/CampaignJourney/audienceRows';
import { loadDraft } from 'dashboard/components-next/CampaignJourney/campaignDraft';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import { campaignsUsingAudience } from 'dashboard/components-next/CampaignJourney/journeyErrors';
import { useAvailableCampaignChannels } from 'dashboard/components-next/CampaignJourney/useAvailableCampaignChannels';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';

const POLL_MS = 1500;
const ACCEPTED_FILES = '.csv,.xlsx';
const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE';

const { t, n } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const name = ref('');
const file = ref(null);
const fileInput = ref(null);
const campaignImport = ref(null);
const isSending = ref(false);
const isApplying = ref(false);
const isSaving = ref(false);
const isChangingSettings = ref(false);
// #1004: SMS badge needs an SMS inbox; a 422 channel_without_inbox also locks it.
const { channels: connectedChannels } = useAvailableCampaignChannels();
const smsInboxRefused = ref(false);
const smsInbox = computed(
  () =>
    !smsInboxRefused.value &&
    connectedChannels.value.includes(CAMPAIGN_CHANNELS.SMS)
);
let pollTimer = null;

const fromCampaign = computed(() => route.query.from === 'campaign');
const draftTitle = computed(() =>
  fromCampaign.value ? loadDraft(accountId.value)?.title?.trim() || '' : ''
);
const phase = computed(() => phaseOf(campaignImport.value));
const canSend = computed(
  () => Boolean(name.value.trim() && file.value) && !isSending.value
);
const refused = computed(() => isRefused(campaignImport.value));
const companies = computed(() => companiesBlock(campaignImport.value));
const savedBadges = computed(() =>
  audienceChannelBadges(campaignImport.value?.channels)
);
const refusedReasons = computed(() => reasonTally(campaignImport.value));
// imported_contacts_count counts every saved row; existing_contacts_count the reused ones.
const newContacts = computed(() =>
  Math.max(
    0,
    (Number(campaignImport.value?.imported_contacts_count) || 0) -
      (Number(campaignImport.value?.existing_contacts_count) || 0)
  )
);
const audienceName = computed(
  () => campaignImport.value?.name || name.value.trim()
);

const stopPolling = () => {
  window.clearTimeout(pollTimer);
  pollTimer = null;
};

const refresh = async () => {
  const { data } = await audiencesAPI.show(campaignImport.value.id);
  campaignImport.value = data.payload;
};

const poll = () => {
  stopPolling();
  if (![PHASES.CHECKING, PHASES.SAVING].includes(phase.value)) return;
  pollTimer = window.setTimeout(async () => {
    try {
      await refresh();
    } finally {
      poll();
    }
  }, POLL_MS);
};

const track = payload => {
  campaignImport.value = payload;
  router.replace({ query: { ...route.query, import: String(payload.id) } });
  poll();
};

const chooseFile = () => fileInput.value?.click();
const onFileChange = () => {
  file.value = fileInput.value?.files?.[0] || null;
};

const send = async () => {
  if (!canSend.value) return;
  isSending.value = true;
  try {
    const { data } = await audiencesAPI.createAudience({
      name: name.value.trim(),
      file: file.value,
    });
    track(data.payload);
  } catch {
    useAlert(t(`${NS}.ERRORS.CREATE`));
  } finally {
    isSending.value = false;
  }
};

const applyColumns = async mapping => {
  isApplying.value = true;
  try {
    const { data } = await audiencesAPI.chooseColumns(
      campaignImport.value.id,
      mapping
    );
    track(data.payload);
  } catch {
    useAlert(t(`${NS}.ERRORS.COLUMNS`));
  } finally {
    isApplying.value = false;
  }
};

const changeSettings = async (request, errorKey) => {
  isChangingSettings.value = true;
  try {
    const { data } = await request();
    campaignImport.value = data.payload;
  } catch (error) {
    if (
      error?.response?.data?.error === 'campaign_import.channel_without_inbox'
    ) {
      smsInboxRefused.value = true;
    }
    const campaigns = campaignsUsingAudience(error);
    useAlert(
      campaigns.length
        ? t(`${NS}.CHANNELS.IN_USE`, { campaigns: campaigns.join(', ') })
        : t(errorKey)
    );
  } finally {
    isChangingSettings.value = false;
  }
};

const toggleChannel = (channel, enabled) =>
  changeSettings(
    () =>
      audiencesAPI.setChannels(campaignImport.value.id, { [channel]: enabled }),
    `${NS}.CHANNELS.ERROR`
  );

const toggleCompanies = enabled =>
  changeSettings(
    () => audiencesAPI.setCreateCompanies(campaignImport.value.id, enabled),
    `${NS}.COMPANIES.ERROR`
  );

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await audiencesAPI.confirm(campaignImport.value.id);
    track(data.payload);
  } catch {
    useAlert(t(`${NS}.ERRORS.SAVE`));
  } finally {
    isSaving.value = false;
  }
};

const downloadProblems = async () => {
  try {
    const response = await audiencesAPI.downloadErrors(campaignImport.value.id);
    const url = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${audienceName.value || 'publico'}_problemas.csv`;
    document.body.appendChild(link);
    link.click();
    window.setTimeout(() => {
      URL.revokeObjectURL(url);
      link.remove();
    }, 1000);
  } catch {
    useAlert(t(`${NS}.ERRORS.DOWNLOAD`));
  }
};

const startOver = () => {
  stopPolling();
  campaignImport.value = null;
  file.value = null;
  const { import: _ignored, ...query } = route.query;
  router.replace({ query });
};

const campaignRoute = query => ({ name: 'campaigns_journey_new', query });

const cancel = () => {
  stopPolling();
  router.push(
    fromCampaign.value
      ? campaignRoute({})
      : { name: 'campaigns_journey_audiences' }
  );
};

const backToCampaign = () =>
  router.push(
    campaignRoute({
      audience: String(campaignImport.value.id),
      returned: '1',
    })
  );

const useInCampaign = () =>
  router.push(campaignRoute({ audience: String(campaignImport.value.id) }));

const reasonText = code => t(`${NS}.REASONS.${reasonKey(code)}`);

// Every visit starts from the address: a new upload, or the audience in `?import=`.
useOnEnter(async () => {
  stopPolling();
  campaignImport.value = null;
  name.value = '';
  file.value = null;
  const importId = route.query.import;
  if (!importId) return;
  try {
    const { data } = await audiencesAPI.show(importId);
    campaignImport.value = data.payload;
    poll();
  } catch {
    useAlert(t(`${NS}.ERRORS.LOAD`));
  }
});

onDeactivated(stopPolling);
onBeforeUnmount(stopPolling);
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
          :to="{ name: 'campaigns_journey_audiences' }"
          class="text-n-slate-11 hover:underline"
        >
          {{ t('CAMPAIGN_JOURNEY.SIDEBAR.AUDIENCES') }}
        </router-link>
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t(`${NS}.TITLE`) }}
        </span>
      </nav>
      <header class="mb-5">
        <h1
          class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
        >
          {{
            phase === PHASES.UPLOAD || !audienceName
              ? t(`${NS}.TITLE`)
              : audienceName
          }}
        </h1>
        <p
          v-if="phase !== PHASES.DONE"
          class="mb-0 mt-2 text-sm leading-6 text-n-slate-11"
        >
          {{
            phase === PHASES.REVIEW
              ? t(`${NS}.REVIEW_SUBTITLE`)
              : t(`${NS}.SUBTITLE`)
          }}
        </p>
      </header>

      <p
        v-if="fromCampaign && phase !== PHASES.DONE"
        class="mb-5 rounded-2xl border border-n-blue-6 bg-n-blue-2 px-4 py-3 text-sm text-n-slate-12"
        data-test="from-campaign"
      >
        {{
          draftTitle
            ? t(`${NS}.FROM_CAMPAIGN`, { name: draftTitle })
            : t(`${NS}.FROM_CAMPAIGN_UNTITLED`)
        }}
      </p>

      <!-- 1. Name + spreadsheet -->
      <form
        v-if="phase === PHASES.UPLOAD"
        class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
        data-test="audience-upload"
        @submit.prevent="send"
      >
        <div>
          <Input
            v-model="name"
            :label="t(`${NS}.NAME_LABEL`)"
            :placeholder="t(`${NS}.NAME_PLACEHOLDER`)"
            :message="t(`${NS}.NAME_HINT`)"
            custom-input-class="!h-11"
            data-test="audience-name"
          />
        </div>
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.FILE_LABEL`) }}
          </span>
          <input
            ref="fileInput"
            type="file"
            class="hidden"
            :accept="ACCEPTED_FILES"
            data-test="audience-file"
            @change="onFileChange"
          />
          <button
            type="button"
            class="flex min-h-32 flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-n-blue-6 bg-n-blue-2 p-5 text-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="chooseFile"
          >
            <span
              class="i-lucide-file-spreadsheet size-7 text-n-blue-11"
              aria-hidden="true"
            />
            <strong class="text-sm text-n-slate-12">
              {{ file ? file.name : t(`${NS}.FILE_CTA`) }}
            </strong>
            <span class="text-xs text-n-slate-11">
              {{ file ? t(`${NS}.FILE_CHANGE`) : t(`${NS}.FILE_HINT`) }}
            </span>
          </button>
        </div>
        <div class="flex flex-wrap justify-between gap-3">
          <Button
            type="button"
            :label="t(`${NS}.CANCEL`)"
            variant="outline"
            color="slate"
            class="!min-h-11 !rounded-xl"
            @click="cancel"
          />
          <Button
            type="submit"
            :label="t(`${NS}.UPLOAD`)"
            :disabled="!canSend"
            :is-loading="isSending"
            class="!min-h-11 !rounded-xl"
            data-test="send-audience"
          />
        </div>
      </form>

      <!-- Reading or saving in the background -->
      <div
        v-else-if="phase === PHASES.CHECKING || phase === PHASES.SAVING"
        class="flex flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-10 text-center shadow-sm"
        role="status"
        data-test="audience-working"
      >
        <Spinner />
        <p class="m-0 font-medium text-n-slate-12">
          {{
            phase === PHASES.SAVING ? t(`${NS}.SAVING`) : t(`${NS}.CHECKING`)
          }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{
            phase === PHASES.SAVING
              ? t(`${NS}.SAVING_HINT`)
              : t(`${NS}.CHECKING_HINT`)
          }}
        </p>
      </div>

      <!-- 2. Review: columns, channels, people, companies -->
      <template v-else-if="phase === PHASES.REVIEW">
        <div
          class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
          data-test="audience-review"
        >
          <AudienceColumns
            :campaign-import="campaignImport"
            :busy="isApplying"
            @apply="applyColumns"
          />
          <section
            v-if="refused"
            class="flex flex-col gap-2 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4"
            role="alert"
            data-test="audience-refused"
          >
            <h2 class="m-0 text-sm font-semibold text-n-ruby-11">
              {{ t(`${NS}.REFUSED.TITLE`) }}
            </h2>
            <p class="m-0 text-sm text-n-slate-12">
              {{ t(`${NS}.REFUSED.HINT`) }}
            </p>
            <ul class="m-0 list-disc ps-5 text-sm text-n-slate-12">
              <li v-for="item in refusedReasons" :key="item.code">
                {{
                  t(`${NS}.PEOPLE.REASON_COUNT`, {
                    reason: reasonText(item.code),
                    count: n(item.count),
                  })
                }}
              </li>
            </ul>
            <div class="flex flex-wrap gap-2">
              <Button
                v-if="campaignImport.downloads?.error_csv"
                :label="t(`${NS}.PEOPLE.DOWNLOAD`)"
                icon="i-lucide-download"
                variant="outline"
                color="slate"
                size="sm"
                class="!min-h-11"
                @click="downloadProblems"
              />
              <Button
                :label="t(`${NS}.REFUSED.ANOTHER`)"
                size="sm"
                class="!min-h-11"
                @click="startOver"
              />
            </div>
          </section>
          <template v-else-if="campaignImport.status === 'ready_to_confirm'">
            <AudienceChannelSwitches
              :channels="campaignImport.channels"
              :sms-inbox="smsInbox"
              :disabled="isChangingSettings"
              @toggle="toggleChannel"
            />
            <AudiencePeople
              :campaign-import="campaignImport"
              @download="downloadProblems"
            />
            <AudienceCompanies
              v-if="companies"
              :block="companies"
              :disabled="isChangingSettings"
              @toggle="toggleCompanies"
            />
          </template>
        </div>
        <div class="mt-5 flex flex-wrap justify-between gap-3">
          <Button
            :label="t(`${NS}.CANCEL`)"
            variant="outline"
            color="slate"
            class="!min-h-11 !rounded-xl"
            data-test="cancel-audience"
            @click="cancel"
          />
          <Button
            v-if="campaignImport.status === 'ready_to_confirm'"
            :label="t(`${NS}.SAVE`)"
            :is-loading="isSaving"
            :disabled="isSaving || isApplying"
            class="!min-h-11 !rounded-xl"
            data-test="save-audience"
            @click="save"
          />
        </div>
      </template>

      <!-- 3. Saved -->
      <div
        v-else-if="phase === PHASES.DONE"
        class="flex flex-col items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-8 text-center shadow-sm"
        data-test="audience-done"
      >
        <span
          class="flex size-14 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
        >
          <span class="i-lucide-check size-7" />
        </span>
        <h2 class="m-0 text-2xl font-semibold text-n-slate-12">
          {{ t(`${NS}.DONE.TITLE`) }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.DONE.SUBTITLE`, { name: audienceName }) }}
        </p>
        <AudienceChannelBadges :badges="savedBadges" />
        <dl class="m-0 grid w-full max-w-2xl grid-cols-2 gap-3 md:grid-cols-4">
          <div class="flex flex-col-reverse rounded-xl bg-n-teal-2 p-3">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.DONE.PEOPLE`) }}
            </dt>
            <dd class="m-0 text-2xl font-semibold tabular-nums">
              {{ n(Number(campaignImport.valid_rows) || 0) }}
            </dd>
          </div>
          <div class="flex flex-col-reverse rounded-xl bg-n-alpha-1 p-3">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.DONE.NEW_CONTACTS`) }}
            </dt>
            <dd class="m-0 text-2xl font-semibold tabular-nums">
              {{ n(newContacts) }}
            </dd>
          </div>
          <div class="flex flex-col-reverse rounded-xl bg-n-alpha-1 p-3">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.DONE.EXISTING_CONTACTS`) }}
            </dt>
            <dd class="m-0 text-2xl font-semibold tabular-nums">
              {{ n(Number(campaignImport.existing_contacts_count) || 0) }}
            </dd>
          </div>
          <div class="flex flex-col-reverse rounded-xl bg-n-amber-2 p-3">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.DONE.LEFT_OUT`) }}
            </dt>
            <dd class="m-0 text-2xl font-semibold tabular-nums">
              {{ n(Number(campaignImport.invalid_rows) || 0) }}
            </dd>
          </div>
        </dl>
        <AudienceCompanies
          v-if="companies && companies.result"
          :block="companies"
          disabled
          class="w-full max-w-2xl text-start"
        />
        <div class="flex flex-wrap justify-center gap-3">
          <template v-if="fromCampaign">
            <Button
              :label="t(`${NS}.DONE.BACK_TO_CAMPAIGN`)"
              class="!min-h-11 !rounded-xl"
              data-test="back-to-campaign"
              @click="backToCampaign"
            />
          </template>
          <template v-else>
            <Button
              :label="t(`${NS}.DONE.SEE_AUDIENCES`)"
              variant="outline"
              color="slate"
              class="!min-h-11 !rounded-xl"
              @click="router.push({ name: 'campaigns_journey_audiences' })"
            />
            <Button
              :label="t(`${NS}.DONE.USE`)"
              class="!min-h-11 !rounded-xl"
              data-test="use-in-campaign"
              @click="useInCampaign"
            />
          </template>
        </div>
      </div>

      <!-- Could not read -->
      <div
        v-else
        class="flex flex-col items-center gap-3 rounded-2xl border border-n-ruby-6 bg-n-solid-1 p-8 text-center"
        role="alert"
        data-test="audience-failed"
      >
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${NS}.FAILED.TITLE`) }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.FAILED.HINT`) }}</p>
        <Button
          :label="t(`${NS}.REFUSED.ANOTHER`)"
          class="!min-h-11 !rounded-xl"
          @click="startOver"
        />
      </div>
    </div>
  </section>
</template>
