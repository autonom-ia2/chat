<script setup>
// Nova campanha (#993, PRD §6.2–6.4, D2, D9): Público → Mensagem → Revisar e agendar, on a
// page with steps. WhatsApp Oficial runs inside the journey; the other channels open their
// existing forms. The draft stays in this browser (campaignDraft.js) so "Criar público" can
// leave and come back with the new audience selected (J2, J3). `?audience=<id>` opens
// Passo 1 with it selected (F3).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

import Button from 'dashboard/components-next/button/Button.vue';
import JourneyStepper from 'dashboard/components-next/CampaignJourney/JourneyStepper.vue';
import StepAudience from 'dashboard/components-next/CampaignJourney/StepAudience.vue';
import StepMessage from 'dashboard/components-next/CampaignJourney/StepMessage.vue';
import StepReview from 'dashboard/components-next/CampaignJourney/StepReview.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';
import WhatsAppApiCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppApiCampaign/WhatsAppApiCampaignDialog.vue';
import SMSCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue';
import LiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue';
import { audiencesAPI, journeyCampaignsAPI } from 'dashboard/api/campaignJourney';
import {
  CAMPAIGN_CHANNELS,
  CHANNEL_LABEL_KEYS,
} from 'dashboard/components-next/CampaignJourney/campaignChannels';
import { useAvailableCampaignChannels } from 'dashboard/components-next/CampaignJourney/useAvailableCampaignChannels';
import {
  reachOn,
  savedAudienceRows,
} from 'dashboard/components-next/CampaignJourney/audienceChannels';
import {
  clearDraft,
  emptyDraft,
  loadDraft,
  saveDraft,
} from 'dashboard/components-next/CampaignJourney/campaignDraft';
import {
  BINDING_SOURCES,
  allBound,
  bindingFromSuggestion,
  buildCampaignPayload,
  cleanDefaults,
  coverageMapping,
  mediaHeaderOf,
  previewMessage,
  templateVariables,
} from 'dashboard/components-next/CampaignJourney/templateVariables';
import {
  accountTimeZone,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { createErrorKey } from 'dashboard/components-next/CampaignJourney/journeyErrors';

const COVERAGE_DELAY_MS = 400;
const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const { channels, features } = useAvailableCampaignChannels();

const accountId = useMapGetter('getCurrentAccountId');
const campaignImports = useMapGetter('campaignImports/getCampaignImports');
const inboxes = useMapGetter('inboxes/getInboxes');
const filteredTemplates = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

const LEGACY_DIALOGS = {
  [CAMPAIGN_CHANNELS.EMAIL]: EmailCampaignDialog,
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: WhatsAppApiCampaignDialog,
  [CAMPAIGN_CHANNELS.SMS]: SMSCampaignDialog,
  [CAMPAIGN_CHANNELS.LIVE_CHAT]: LiveChatCampaignDialog,
};

const draft = ref(emptyDraft());
const extraImports = ref([]);
const isLoading = ref(true);
const hasLoadError = ref(false);
const coverage = ref(null);
const sample = ref(null);
const legacyChannel = ref('');
const isSubmitting = ref(false);
const submitError = ref('');
const returned = ref(route.query.returned === '1');
let coverageTimer = null;

// A new template (or inbox) starts its variables from scratch.
const update = patch => {
  const templateChanged =
    'templateId' in patch && patch.templateId !== draft.value.templateId;
  draft.value = {
    ...draft.value,
    ...(templateChanged ? { bindings: {}, defaults: {}, mediaUrl: '' } : {}),
    ...patch,
  };
};

// ---- Audience (Passo 1) ----
const allImports = computed(() => {
  const loaded = campaignImports.value || [];
  const missing = extraImports.value.filter(
    extra => !loaded.some(item => item.id === extra.id)
  );
  return [...missing, ...loaded];
});
const audienceRows = computed(() => savedAudienceRows(allImports.value));
const audience = computed(
  () => audienceRows.value.find(row => row.id === draft.value.audienceId) || null
);
const audienceImport = computed(() =>
  allImports.value.find(item => item.id === draft.value.audienceId)
);
const columns = computed(() => audienceImport.value?.extra_columns || []);
const showLiveChat = computed(() =>
  channels.value.includes(CAMPAIGN_CHANNELS.LIVE_CHAT)
);

// ---- Message (Passo 2) ----
const cloudInboxes = computed(() =>
  (inboxes.value || []).filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP &&
      inbox.provider === 'whatsapp_cloud'
  )
);
const inboxOptions = computed(() =>
  cloudInboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const templates = computed(() =>
  draft.value.inboxId ? filteredTemplates.value(draft.value.inboxId) : []
);
const templateOptions = computed(() =>
  templates.value.map(template => ({
    value: template.id,
    label: `${template.name} · ${template.language || ''}`,
  }))
);
const template = computed(
  () =>
    templates.value.find(item => item.id === draft.value.templateId) || null
);
const variables = computed(() =>
  template.value ? templateVariables(template.value) : []
);
const mediaHeader = computed(() =>
  template.value ? mediaHeaderOf(template.value) : null
);

const sourceLabel = binding => {
  if (binding.source === BINDING_SOURCES.COLUMN) return binding.value;
  if (binding.source === BINDING_SOURCES.FIXED) return binding.value;
  return t(`${NS}.VARIABLES.CONTACT_FIELDS.${binding.value.toUpperCase()}`);
};

const previewText = computed(() =>
  template.value
    ? previewMessage({
        template: template.value,
        bindings: draft.value.bindings,
        defaults: cleanDefaults(draft.value.defaults),
        sample: sample.value,
        placeholder: binding => `[${sourceLabel(binding)}]`,
      })
    : ''
);

const isMessageReady = computed(
  () =>
    draft.value.channel === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL &&
    Boolean(draft.value.title.trim()) &&
    Boolean(draft.value.inboxId) &&
    Boolean(template.value) &&
    allBound(variables.value, draft.value.bindings) &&
    (!mediaHeader.value || Boolean(draft.value.mediaUrl.trim()))
);

// ---- Review (Passo 3) ----
const timeZone = computed(() => accountTimeZone(currentAccount.value));
const reach = computed(() =>
  audience.value
    ? reachOn(CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL, audience.value.channels)
    : 0
);
const inboxName = computed(
  () =>
    cloudInboxes.value.find(inbox => inbox.id === draft.value.inboxId)?.name ||
    ''
);
const bindingSummary = computed(() =>
  variables.value
    .filter(({ key }) => draft.value.bindings[key])
    .map(({ key }) => `{{${key}}} ${sourceLabel(draft.value.bindings[key])}`)
    .join(' · ')
);

const reachable = computed(() => {
  if (!audience.value) return 1;
  return isMessageReady.value ? 3 : 2;
});

const goTo = step => {
  update({ step: Math.min(step, reachable.value) });
  submitError.value = '';
};

// ---- Suggestions and coverage ----
const applySuggestions = async () => {
  if (!template.value || !draft.value.audienceId || !variables.value.length) {
    return;
  }
  try {
    const { data } = await audiencesAPI.variableSuggestions(
      draft.value.audienceId,
      variables.value
    );
    const bindings = { ...draft.value.bindings };
    (data?.payload || []).forEach(suggestion => {
      const binding = bindingFromSuggestion(suggestion);
      if (binding && !bindings[suggestion.key]) {
        bindings[suggestion.key] = binding;
      }
    });
    update({ bindings });
  } catch {
    // No suggestion: the person chooses each source.
  }
};

const refreshCoverage = () => {
  window.clearTimeout(coverageTimer);
  const mapping = coverageMapping(draft.value.bindings);
  if (!draft.value.audienceId || !Object.keys(mapping).length) {
    coverage.value = null;
    return;
  }
  coverageTimer = window.setTimeout(async () => {
    try {
      const { data } = await audiencesAPI.variableCoverage(
        draft.value.audienceId,
        { mapping, defaults: cleanDefaults(draft.value.defaults) }
      );
      coverage.value = data?.payload || null;
    } catch {
      coverage.value = null;
    }
  }, COVERAGE_DELAY_MS);
};

const loadSample = async () => {
  sample.value = null;
  if (!draft.value.audienceId) return;
  try {
    const { data } = await audiencesAPI.sampleContact(draft.value.audienceId);
    sample.value = data?.payload || null;
  } catch {
    // Not available yet (api-993-frontend-needs.md §3): the preview shows labels.
  }
};

const bind = (key, binding) =>
  update({ bindings: { ...draft.value.bindings, [key]: binding } });
const setDefault = (key, value) =>
  update({ defaults: { ...draft.value.defaults, [key]: value } });

watch(() => [template.value?.id, draft.value.audienceId], applySuggestions);
watch(
  () => [draft.value.audienceId, draft.value.bindings, draft.value.defaults],
  refreshCoverage,
  { deep: true }
);
watch(() => draft.value.audienceId, loadSample);
watch(draft, value => saveDraft(accountId.value, value), { deep: true });

// ---- Actions ----
const selectAudience = id => {
  returned.value = false;
  update({ audienceId: id });
};

const createAudience = () => {
  saveDraft(accountId.value, draft.value);
  router.push({
    name: 'campaigns_journey_audience_new',
    query: { from: 'campaign' },
  });
};

const openLegacy = channel => {
  legacyChannel.value = channel;
};
const closeLegacy = () => {
  legacyChannel.value = '';
};
const onLegacyCreated = () => {
  closeLegacy();
  clearDraft(accountId.value);
  router.push({ name: 'campaigns_journey_index' });
};

const cancel = () => {
  clearDraft(accountId.value);
  router.push({ name: 'campaigns_journey_index' });
};

const submit = async () => {
  isSubmitting.value = true;
  submitError.value = '';
  try {
    await journeyCampaignsAPI.create(
      buildCampaignPayload({
        audienceId: draft.value.audienceId,
        title: draft.value.title,
        inboxId: draft.value.inboxId,
        scheduledAt:
          draft.value.when === 'later'
            ? scheduleToUtc(draft.value.scheduledAt, timeZone.value)
            : null,
        template: template.value,
        bindings: draft.value.bindings,
        defaults: draft.value.defaults,
        mediaUrl: draft.value.mediaUrl,
      })
    );
    clearDraft(accountId.value);
    useAlert(t(`${NS}.REVIEW.SUCCESS`));
    router.push({
      name: 'campaigns_journey_index',
      query: { channel: CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL },
    });
  } catch (error) {
    submitError.value = t(`${NS}.REVIEW.ERRORS.${createErrorKey(error)}`);
  } finally {
    isSubmitting.value = false;
  }
};

const loadAudienceFromQuery = async id => {
  if (allImports.value.some(item => item.id === id)) return;
  try {
    const { data } = await audiencesAPI.show(id);
    extraImports.value = [data.payload];
  } catch {
    // Unknown or from another account: Passo 1 just shows the list.
  }
};

onMounted(async () => {
  // Back from Novo público (J3) keeps the draft; "Usar em nova campanha" (F3) starts fresh.
  const stored = loadDraft(accountId.value) || emptyDraft();
  const queryAudience = Number(route.query.audience) || null;
  const base = route.query.returned === '1' ? stored : emptyDraft();
  draft.value = queryAudience
    ? { ...base, audienceId: queryAudience, step: 1 }
    : stored;

  const requests = [
    store.dispatch('campaignImports/get'),
    store.dispatch('inboxes/get'),
  ];
  if (features.value.emailCampaigns) {
    requests.push(store.dispatch('emailSenderIdentities/get'));
  }
  const results = await Promise.allSettled(requests);
  hasLoadError.value = results[0].status === 'rejected';
  if (queryAudience) await loadAudienceFromQuery(queryAudience);
  isLoading.value = false;
  if (draft.value.step > reachable.value) update({ step: reachable.value });
  loadSample();
  refreshCoverage();
});

onBeforeUnmount(() => window.clearTimeout(coverageTimer));
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
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
          {{ t(`${NS}.TITLE`) }}
        </span>
      </nav>
      <header class="mb-5 flex flex-wrap items-center justify-between gap-3">
        <h1
          class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
        >
          {{ t(`${NS}.TITLE`) }}
        </h1>
        <Button
          :label="t(`${NS}.CANCEL`)"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          data-test="cancel-campaign"
          @click="cancel"
        />
      </header>

      <JourneyStepper
        :current="draft.step"
        :reachable="reachable"
        @go="goTo"
      />

      <div v-if="legacyChannel" class="relative mb-4 flex justify-end">
        <component
          :is="LEGACY_DIALOGS[legacyChannel]"
          @saved="onLegacyCreated"
          @created="onLegacyCreated"
          @close="closeLegacy"
        />
      </div>

      <StepAudience
        v-if="draft.step === 1"
        :rows="audienceRows"
        :selected-id="draft.audienceId"
        :is-loading="isLoading"
        :has-load-error="hasLoadError"
        :returned-name="returned && audience ? audience.name : ''"
        :show-live-chat="showLiveChat"
        @select="selectAudience"
        @create="createAudience"
        @live-chat="openLegacy(CAMPAIGN_CHANNELS.LIVE_CHAT)"
        @continue="goTo(2)"
      />

      <StepMessage
        v-else-if="draft.step === 2 && audience"
        :audience="audience"
        :channels="channels"
        :draft="draft"
        :inbox-options="inboxOptions"
        :template-options="templateOptions"
        :variables="variables"
        :columns="columns"
        :coverage="coverage"
        :media-header="mediaHeader"
        :preview-text="previewText"
        :can-continue="isMessageReady"
        @update="update"
        @bind="bind"
        @default="setDefault"
        @legacy="openLegacy"
        @change-audience="goTo(1)"
        @back="goTo(1)"
        @continue="goTo(3)"
      />

      <StepReview
        v-else-if="draft.step === 3 && audience && template"
        :audience="audience"
        :draft="draft"
        :channel-label="
          t(
            `CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]}`
          )
        "
        :inbox-name="inboxName"
        :template-name="template.name"
        :binding-summary="bindingSummary"
        :reach="reach"
        :excluded="coverage ? Number(coverage.excluded_count) || 0 : null"
        :time-zone="timeZone"
        :is-submitting="isSubmitting"
        :error-message="submitError"
        @update="update"
        @go="goTo"
        @back="goTo(2)"
        @submit="submit"
      />
    </div>
  </section>
</template>
