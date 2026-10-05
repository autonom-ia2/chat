<script setup>
// Nova campanha (#993, PRD §6.2–6.4, D2, D9): Público → Mensagem → Revisar e agendar, on a
// page with steps. WhatsApp Oficial, WhatsApp API, SMS (#1004) and e-mail run inside the
// journey (the e-mail content in the existing editor); Chat ao vivo has its own flow
// (LiveChatJourneyPage). The draft stays in this browser (campaignDraft.js) so "Criar público" can
// leave and come back with the new audience selected (J2, J3). `?audience=<id>` opens
// Passo 1 with it selected (F3).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
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
import EmailCampaignsAPI from 'dashboard/api/emailCampaigns';
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
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import { JOURNEY_EDITOR_QUERY } from './journeyRedirects';
import { smsStats } from 'dashboard/components-next/CampaignJourney/smsSegments';
import { useJourneyChannelForms } from 'dashboard/components-next/CampaignJourney/useJourneyChannelForms';
import {
  buildEmailPayload,
  buildSmsPayload,
  buildWhatsappApiPayload,
  emailChecks,
} from 'dashboard/components-next/CampaignJourney/journeyChannelPayloads';

const COVERAGE_DELAY_MS = 400;
const SEARCH_DELAY_MS = 300;
const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const { channels, features } = useAvailableCampaignChannels();

const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const filteredTemplates = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

const currentUser = useMapGetter('getCurrentUser');


const draft = ref(emptyDraft());
const listedImports = ref([]);
const listMeta = ref({ count: 0, page: 1 });
const searchQuery = ref('');
const audienceDetail = ref(null);
let searchTimer = null;
const isLoading = ref(true);
const hasLoadError = ref(false);
const coverage = ref(null);
const sample = ref(null);
const isSubmitting = ref(false);
const submitError = ref('');
const returned = ref(route.query.returned === '1');
const isCreatingEmail = ref(false);
const isTestSending = ref(false);
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
// Saved audiences come from the server (saved=true, q, page); the chosen one is read with
// `show`, which also brings who does not receive (reachability, PRD B8).
const allImports = computed(() => {
  const detail = audienceDetail.value;
  const listed = listedImports.value.map(item =>
    detail && item.id === detail.id ? detail : item
  );
  const missing = detail && !listed.some(item => item.id === detail.id);
  return missing ? [detail, ...listed] : listed;
});
const hasMoreAudiences = computed(
  () => listedImports.value.length < Number(listMeta.value.count || 0)
);
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

// Bindings as the backend reads them (without the "Sugerido" flag).
const plainBindings = () =>
  Object.fromEntries(
    Object.entries(draft.value.bindings).map(([key, { source, value }]) => [
      key,
      { source, value },
    ])
  );
const forms = useJourneyChannelForms({ draft, bindings: plainBindings });

const isOfficialReady = computed(
  () =>
    Boolean(draft.value.inboxId) &&
    Boolean(template.value) &&
    allBound(variables.value, draft.value.bindings) &&
    (!mediaHeader.value || Boolean(draft.value.mediaUrl.trim()))
);
const MESSAGE_READY = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: () => isOfficialReady.value,
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: () =>
    Boolean(draft.value.inboxId) && Boolean(draft.value.messageBody.trim()),
  [CAMPAIGN_CHANNELS.EMAIL]: () => Boolean(draft.value.emailCampaignId),
  [CAMPAIGN_CHANNELS.SMS]: () =>
    Boolean(draft.value.inboxId) && Boolean(draft.value.messageBody.trim()),
};
const isMessageReady = computed(
  () =>
    Boolean(draft.value.title.trim()) &&
    Boolean(MESSAGE_READY[draft.value.channel]?.())
);

// ---- Review (Passo 3) ----
const timeZone = computed(() => accountTimeZone(currentAccount.value));
const isEmailChannel = computed(
  () => draft.value.channel === CAMPAIGN_CHANNELS.EMAIL
);
const reach = computed(() =>
  audience.value && draft.value.channel
    ? reachOn(draft.value.channel, audience.value.channels)
    : 0
);
const inboxName = computed(
  () =>
    (forms.inboxes.value || []).find(inbox => inbox.id === draft.value.inboxId)
      ?.name || ''
);
const channelLabel = computed(() =>
  draft.value.channel
    ? t(`CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[draft.value.channel]}`)
    : ''
);
const bindingSummary = computed(() =>
  variables.value
    .filter(({ key }) => draft.value.bindings[key])
    .map(
      ({ key, variable }) =>
        `{{${variable}}} ${sourceLabel(draft.value.bindings[key])}`
    )
    .join(' · ')
);

const emailSenderText = computed(() => {
  const email = forms.emailCampaign.value;
  return [email?.from_name, email?.from_email].filter(Boolean).join(' · ');
});
const messageDetail = () => {
  if (draft.value.channel === CAMPAIGN_CHANNELS.SMS) {
    return t(`${NS}.SMS.DETAIL`, {
      inbox: inboxName.value,
      segments: smsStats(draft.value.messageBody).segments,
    });
  }
  if (draft.value.channel === CAMPAIGN_CHANNELS.WHATSAPP_API) {
    return t(`${NS}.REVIEW.API_DETAIL`, { inbox: inboxName.value });
  }
  if (isEmailChannel.value) {
    return t(`${NS}.REVIEW.EMAIL_DETAIL`, { sender: emailSenderText.value });
  }
  return [
    t(`${NS}.REVIEW.CHANNEL_DETAIL`, { inbox: inboxName.value }),
    bindingSummary.value,
  ]
    .filter(Boolean)
    .join(' · ');
};
const messageMain = () => {
  if (
    [CAMPAIGN_CHANNELS.WHATSAPP_API, CAMPAIGN_CHANNELS.SMS].includes(
      draft.value.channel
    )
  ) {
    return draft.value.messageBody;
  }
  if (isEmailChannel.value) {
    return forms.emailCampaign.value?.subject
      ? t(`${NS}.REVIEW.CONTENT_DETAIL`, {
          subject: forms.emailCampaign.value.subject,
        })
      : t(`${NS}.EMAIL.CONTENT_EMPTY`);
  }
  return template.value?.name || '';
};
const reviewBlocks = computed(() => [
  {
    key: 'audience',
    step: 1,
    title: t(`${NS}.REVIEW.AUDIENCE`),
    main: audience.value?.name || '',
    detail: '',
  },
  {
    key: 'message',
    step: 2,
    title: t(`${NS}.REVIEW.CHANNEL`),
    main: `${channelLabel.value} · ${draft.value.title.trim()}`,
    detail: messageDetail(),
  },
  {
    key: 'content',
    step: 2,
    title: t(`${NS}.REVIEW.CONTENT`),
    main: messageMain(),
    detail: '',
  },
]);
const crmTag = computed(() =>
  t(`${NS}.MESSAGE.CRM_TAG`, { name: draft.value.title.trim() })
);
const onChannelLabel = computed(() =>
  isEmailChannel.value
    ? t(`${NS}.REVIEW.ON_CHANNEL_EMAIL`)
    : t(`${NS}.REVIEW.ON_CHANNEL`)
);
const reviewChecks = computed(() =>
  isEmailChannel.value ? emailChecks(forms.emailCampaign.value) : []
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
      variables.value.map(({ key, label }) => ({ key, label }))
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

// One source per value: a getter returning a new array would fire on every draft update.
watch(
  [() => template.value?.id, () => draft.value.audienceId],
  applySuggestions
);
watch(
  [
    () => draft.value.audienceId,
    () => JSON.stringify(draft.value.bindings),
    () => JSON.stringify(draft.value.defaults),
  ],
  refreshCoverage
);
watch(
  () => draft.value.audienceId,
  () => {
    loadSample();
    loadAudienceDetail();
  }
);
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

const cancel = () => {
  clearDraft(accountId.value);
  router.push({ name: 'campaigns_journey_index' });
};

const scheduledAtValue = () =>
  draft.value.when === 'later'
    ? scheduleToUtc(draft.value.scheduledAt, timeZone.value)
    : null;

const SUBMITTERS = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: () =>
    journeyCampaignsAPI.create(
      buildCampaignPayload({
        audienceId: draft.value.audienceId,
        title: draft.value.title,
        inboxId: draft.value.inboxId,
        scheduledAt: scheduledAtValue(),
        template: template.value,
        bindings: draft.value.bindings,
        defaults: draft.value.defaults,
        mediaUrl: draft.value.mediaUrl,
      })
    ),
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: () => {
    const payload = buildWhatsappApiPayload({
      audienceId: draft.value.audienceId,
      draft: draft.value,
      scheduledAt: scheduledAtValue(),
    });
    const file = forms.mediaFile.value;
    return file
      ? journeyCampaignsAPI.createWithFile({
          ...payload,
          campaign: { ...payload.campaign, media_file: file },
        })
      : journeyCampaignsAPI.create(payload);
  },
  [CAMPAIGN_CHANNELS.SMS]: () =>
    journeyCampaignsAPI.create(
      buildSmsPayload({
        audienceId: draft.value.audienceId,
        draft: draft.value,
        scheduledAt: scheduledAtValue(),
      })
    ),
  // The e-mail draft exists since Passo 2: schedule it or send it now (engine endpoints).
  [CAMPAIGN_CHANNELS.EMAIL]: () => {
    const id = draft.value.emailCampaignId;
    const at = scheduledAtValue();
    return at ? EmailCampaignsAPI.schedule(id, at) : EmailCampaignsAPI.sendNow(id);
  },
};

const submit = async () => {
  isSubmitting.value = true;
  submitError.value = '';
  try {
    const channel = draft.value.channel;
    await SUBMITTERS[channel]();
    clearDraft(accountId.value);
    forms.mediaFile.value = null;
    useAlert(t(`${NS}.REVIEW.SUCCESS`));
    router.push({ name: 'campaigns_journey_index', query: { channel } });
  } catch (error) {
    submitError.value = t(`${NS}.REVIEW.ERRORS.${createErrorKey(error)}`);
  } finally {
    isSubmitting.value = false;
  }
};

const createEmail = async () => {
  isCreatingEmail.value = true;
  submitError.value = '';
  try {
    const { data } = await journeyCampaignsAPI.create(
      buildEmailPayload({ audienceId: draft.value.audienceId, draft: draft.value })
    );
    update({ emailCampaignId: data.id });
  } catch (error) {
    const key = createErrorKey(error);
    useAlert(
      key === 'GENERIC'
        ? t(`${NS}.EMAIL.ERROR`)
        : t(`${NS}.REVIEW.ERRORS.${key}`)
    );
  } finally {
    isCreatingEmail.value = false;
  }
};

// The existing editor, unchanged; the draft brings the person back to Passo 2.
const openEmailEditor = () => {
  saveDraft(accountId.value, draft.value);
  router.push({
    name: 'campaigns_email_builder',
    params: { campaignId: draft.value.emailCampaignId },
    query: { [JOURNEY_EDITOR_QUERY]: '1' },
  });
};

// "Enviar teste para mim" (D8): only the logged-in user's address (api-999.md §4).
const sendTestToMe = async () => {
  isTestSending.value = true;
  try {
    const email = currentUser.value?.email;
    await EmailCampaignsAPI.sendTest(draft.value.emailCampaignId, email);
    useAlert(t(`${NS}.REVIEW.TEST_SENT`, { email }));
  } catch {
    useAlert(t(`${NS}.REVIEW.TEST_ERROR`));
  } finally {
    isTestSending.value = false;
  }
};

// Sent or scheduled from the editor itself (same backend checks): the journey draft is done.
watch(
  () => forms.emailCampaign.value?.status,
  status => {
    if (!status || status === 'draft') return;
    clearDraft(accountId.value);
    router.replace({
      name: 'campaigns_journey_index',
      query: { channel: CAMPAIGN_CHANNELS.EMAIL },
    });
  }
);

const openLiveChat = () =>
  router.push({ name: 'campaigns_journey_live_chat_new' });

const loadAudiences = async ({ append = false } = {}) => {
  const page = append ? Number(listMeta.value.page || 1) + 1 : 1;
  const { data } = await audiencesAPI.list({
    saved: true,
    q: searchQuery.value.trim(),
    page,
  });
  const payload = data?.payload || [];
  listedImports.value = append ? [...listedImports.value, ...payload] : payload;
  listMeta.value = { count: data?.meta?.count || 0, page };
};

const searchAudiences = query => {
  searchQuery.value = query;
  window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(async () => {
    try {
      hasLoadError.value = false;
      await loadAudiences();
    } catch {
      hasLoadError.value = true;
    }
  }, SEARCH_DELAY_MS);
};

const loadMoreAudiences = async () => {
  try {
    await loadAudiences({ append: true });
  } catch {
    hasLoadError.value = true;
  }
};

const loadAudienceDetail = async () => {
  const id = draft.value.audienceId;
  if (!id) {
    audienceDetail.value = null;
    return;
  }
  try {
    const { data } = await audiencesAPI.show(id);
    if (draft.value.audienceId === id) audienceDetail.value = data.payload;
  } catch {
    // Unknown or from another account: Passo 1 just shows the list.
  }
};

// Every visit (first mount or back to the kept-alive page) reads the draft and the address.
useOnEnter(async () => {
  // Back from Novo público (J3) keeps the draft; "Usar em nova campanha" (F3) starts fresh.
  isLoading.value = true;
  submitError.value = '';
  returned.value = route.query.returned === '1';
  const stored = loadDraft(accountId.value) || emptyDraft();
  const queryAudience = Number(route.query.audience) || null;
  const base = route.query.returned === '1' ? stored : emptyDraft();
  draft.value = queryAudience
    ? { ...base, audienceId: queryAudience, step: 1 }
    : stored;

  searchQuery.value = '';
  audienceDetail.value = null;
  const requests = [loadAudiences(), store.dispatch('inboxes/get')];
  if (features.value.emailCampaigns) {
    requests.push(store.dispatch('emailSenderIdentities/get'));
  }
  const results = await Promise.allSettled(requests);
  hasLoadError.value = results[0].status === 'rejected';
  await loadAudienceDetail();
  forms.loadEmailCampaign();
  forms.loadApiTemplates(draft.value.inboxId);
  forms.refreshPreview();
  isLoading.value = false;
  if (draft.value.step > reachable.value) update({ step: reachable.value });
  loadSample();
  refreshCoverage();
});

onBeforeUnmount(() => {
  forms.stop();
  window.clearTimeout(coverageTimer);
  window.clearTimeout(searchTimer);
});
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


      <StepAudience
        v-if="draft.step === 1"
        :rows="audienceRows"
        :selected-id="draft.audienceId"
        :is-loading="isLoading"
        :has-load-error="hasLoadError"
        :returned-name="returned && audience ? audience.name : ''"
        :show-live-chat="showLiveChat"
        :search-query="searchQuery"
        :has-more="hasMoreAudiences"
        @search="searchAudiences"
        @load-more="loadMoreAudiences"
        @select="selectAudience"
        @create="createAudience"
        @live-chat="openLiveChat"
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
        :api-form="{
          inboxOptions: forms.apiInboxOptions.value,
          templates: forms.apiTemplates.value,
          extraColumns: columns,
          mediaFile: forms.mediaFile.value,
          preview: forms.preview.value,
        }"
        :email-form="{
          identities: forms.identities.value || [],
          inboxes: forms.inboxes.value || [],
          emailCampaign: forms.emailCampaign.value,
          isCreating: isCreatingEmail,
        }"
        :sms-form="{
          inboxOptions: forms.smsInboxOptions.value,
          extraColumns: columns,
          sample,
          preview: forms.preview.value,
        }"
        @attach="file => (forms.mediaFile.value = file)"
        @email-create="createEmail"
        @open-editor="openEmailEditor"
        @email-reload="forms.loadEmailCampaign"
        @update="update"
        @bind="bind"
        @default="setDefault"
        @change-audience="goTo(1)"
        @back="goTo(1)"
        @continue="goTo(3)"
      />

      <StepReview
        v-else-if="draft.step === 3 && audience && isMessageReady"
        :draft="draft"
        :blocks="reviewBlocks"
        :channel-label="channelLabel"
        :on-channel-label="onChannelLabel"
        :crm-tag="crmTag"
        :reach="reach"
        :preview="forms.preview.value"
        :checks="reviewChecks"
        :show-test-send="isEmailChannel"
        :is-test-sending="isTestSending"
        :time-zone="timeZone"
        :is-submitting="isSubmitting"
        :error-message="submitError"
        @update="update"
        @go="goTo"
        @back="goTo(2)"
        @submit="submit"
        @test-send="sendTestToMe"
      />
    </div>
  </section>
</template>
