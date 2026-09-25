<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BaseSettingsHeader from '../../../settings/components/BaseSettingsHeader.vue';
import ProspectingAiCredentialNotice from '../components/ProspectingAiCredentialNotice.vue';
import ProspectingMockProviderNotice from '../components/ProspectingMockProviderNotice.vue';
import ProspectingOrthScoreWeights from '../components/ProspectingOrthScoreWeights.vue';
import ProspectingSearchCountryField from '../components/ProspectingSearchCountryField.vue';
import { DEFAULT_SEARCH_COUNTRY } from '../utils/searchCountries';

const { t } = useI18n();

const isLoading = ref(true);
const isSaving = ref(false);
const hasLoadError = ref(false);
const settings = ref(null);
const crmPipelines = ref([]);
const crmStages = ref([]);
const scoringProfiles = ref([]);
const activeSettingsTab = ref('general');
const CUSTOM_SCORING_PROFILE_VALUE = 'custom';
const scoringWeightKeys = [
  'website',
  'phone',
  'rating',
  'reviews_count',
  'activity',
  'photos',
  'google_rank',
  'query_relevance',
];
const form = ref({
  cache_ttl_seconds: 86400,
  default_crm_pipeline_id: '',
  default_crm_stage_id: '',
  search_score_mode: 'gbp',
  search_country: DEFAULT_SEARCH_COUNTRY,
  scoring_profile_option: '',
  scoring_profile_id: '',
  custom_scoring_weights: {
    website: 25,
    phone: 10,
    rating: 20,
    reviews_count: 15,
    activity: 10,
    photos: 10,
    google_rank: 5,
    query_relevance: 5,
  },
});

// Chave pronta só vale quando a conta busca no Google: em mock, a busca devolve
// empresas inventadas e a tela não pode dizer que usa a chave da plataforma.
const keysReady = computed(
  () =>
    Boolean(settings.value?.platform_google_places_configured) &&
    !settings.value?.mock_provider
);
const keysStatusText = computed(() => {
  if (settings.value?.mock_provider) {
    return t('PROSPECTING.SETTINGS.PLATFORM.KEYS_MOCK');
  }
  return keysReady.value
    ? t('PROSPECTING.SETTINGS.PLATFORM.KEYS_READY')
    : t('PROSPECTING.SETTINGS.PLATFORM.KEYS_MISSING');
});

const pipelineChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SETTINGS.CRM_EMPTY') },
  ...crmPipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  })),
]);
const stageChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SETTINGS.CRM_STAGE_EMPTY') },
  ...crmStages.value.map(stage => ({ value: stage.id, label: stage.name })),
]);
const searchScoreModeChoices = computed(() => [
  { value: 'gbp', label: t('PROSPECTING.SETTINGS.SEARCH_SCORE_MODES.GBP') },
  {
    value: 'general',
    label: t('PROSPECTING.SETTINGS.SEARCH_SCORE_MODES.GENERAL'),
  },
]);
const scoringProfileChoices = computed(() => [
  ...scoringProfiles.value.map(profile => ({
    value: profile.id,
    label: profile.name,
  })),
  {
    value: CUSTOM_SCORING_PROFILE_VALUE,
    label: t('PROSPECTING.SETTINGS.SCORING_PROFILE_CUSTOM'),
  },
]);
const selectedScoringProfile = computed(() =>
  scoringProfiles.value.find(
    profile => Number(profile.id) === Number(form.value.scoring_profile_option)
  )
);

const isCustomScoringProfile = computed(
  () => form.value.scoring_profile_option === CUSTOM_SCORING_PROFILE_VALUE
);

// Conta virada para a nota do Orth (#681). Conta legacy não recebe pesos do
// Orth no payload e vê a aba como sempre foi.
const isOrthEngine = computed(() => settings.value?.score_engine === 'orth');

const orthScoringWeights = computed(() => {
  if (isCustomScoringProfile.value) return settings.value?.orth_scoring_weights;

  return (
    selectedScoringProfile.value?.orth_weights ||
    settings.value?.orth_scoring_weights
  );
});

const scoringProfileBadge = computed(() => {
  if (isCustomScoringProfile.value) {
    return t('PROSPECTING.SETTINGS.SCORING_PROFILE_CUSTOM');
  }
  return selectedScoringProfile.value?.restricted
    ? t('PROSPECTING.SETTINGS.SCORING_PROFILE_RESTRICTED')
    : t('PROSPECTING.SETTINGS.SCORING_PROFILE_GLOBAL');
});

const displayedScoringWeights = computed(() => {
  if (isCustomScoringProfile.value) {
    return form.value.custom_scoring_weights;
  }

  return (
    selectedScoringProfile.value?.weights ||
    settings.value?.active_scoring_weights ||
    form.value.custom_scoring_weights
  );
});

const syncForm = payload => {
  settings.value = payload;
  scoringProfiles.value = payload.scoring_profiles || [];
  const defaultProfile =
    scoringProfiles.value.find(profile => profile.default) ||
    scoringProfiles.value[0];
  form.value = {
    cache_ttl_seconds: payload.cache_ttl_seconds || 86400,
    default_crm_pipeline_id: payload.default_crm_pipeline_id || '',
    default_crm_stage_id: payload.default_crm_stage_id || '',
    search_score_mode: payload.search_score_mode || 'gbp',
    search_country: payload.search_country || DEFAULT_SEARCH_COUNTRY,
    scoring_profile_option:
      payload.scoring_mode === 'custom'
        ? CUSTOM_SCORING_PROFILE_VALUE
        : payload.scoring_profile_id || defaultProfile?.id || '',
    scoring_profile_id: payload.scoring_profile_id || defaultProfile?.id || '',
    custom_scoring_weights: {
      ...form.value.custom_scoring_weights,
      ...(payload.custom_scoring_weights ||
        payload.active_scoring_weights ||
        {}),
    },
  };
};

const fetchCrmStages = async pipelineId => {
  crmStages.value = [];
  form.value.default_crm_stage_id = '';
  if (!pipelineId) return;

  const { data } = await CrmKanbanAPI.getStages(pipelineId);
  crmStages.value = data.payload || [];
  form.value.default_crm_stage_id =
    settings.value?.default_crm_stage_id || crmStages.value[0]?.id || '';
};

const fetchCrmPipelines = async () => {
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    crmPipelines.value = data.payload || [];
  } catch {
    crmPipelines.value = [];
  }
};

const weightPercent = key =>
  Math.max(0, Math.min(100, Number(displayedScoringWeights.value[key] || 0)));

const fetchSettings = async () => {
  isLoading.value = true;
  hasLoadError.value = false;
  try {
    const [{ data }] = await Promise.all([
      AutonomiaProspectingAPI.getSettings(),
      fetchCrmPipelines(),
    ]);
    syncForm(data.payload || {});
    await fetchCrmStages(form.value.default_crm_pipeline_id);
  } catch {
    hasLoadError.value = true;
    useAlert(t('PROSPECTING.ERRORS.LOAD_SETTINGS'));
  } finally {
    isLoading.value = false;
  }
};

const saveSettings = async () => {
  isSaving.value = true;

  try {
    const { data } = await AutonomiaProspectingAPI.updateSettings({
      cache_ttl_seconds: Number(form.value.cache_ttl_seconds),
      default_crm_pipeline_id: form.value.default_crm_pipeline_id || null,
      default_crm_stage_id: form.value.default_crm_stage_id || null,
      search_score_mode: form.value.search_score_mode || 'gbp',
      search_country: form.value.search_country,
      scoring_mode: isCustomScoringProfile.value ? 'custom' : 'profile',
      scoring_profile_id: isCustomScoringProfile.value
        ? null
        : form.value.scoring_profile_option || null,
      custom_scoring_weights: scoringWeightKeys.reduce((weights, key) => {
        weights[key] = Number(form.value.custom_scoring_weights[key] || 0);
        return weights;
      }, {}),
    });
    syncForm(data.payload || {});
    useAlert(t('PROSPECTING.SETTINGS.SAVED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('PROSPECTING.ERRORS.SAVE_SETTINGS'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchSettings);
</script>

<template>
  <main class="flex min-h-full w-full flex-col">
    <div class="mb-6">
      <BaseSettingsHeader
        :title="t('PROSPECTING.SETTINGS.TITLE')"
        :description="t('PROSPECTING.SETTINGS.DESCRIPTION')"
      />
    </div>
    <section class="grid w-full gap-3">
      <div
        v-if="isLoading"
        class="rounded-lg border border-n-weak bg-n-solid-1 px-4 py-8 text-sm text-n-slate-11"
      >
        {{ t('PROSPECTING.STATES.LOADING') }}
      </div>
      <div
        v-else-if="hasLoadError"
        class="rounded-lg border border-n-weak bg-n-solid-1 px-4 py-8"
      />
      <form
        v-else
        class="grid gap-4 rounded-lg border border-n-weak bg-n-solid-1 p-4 text-sm"
        @submit.prevent="saveSettings"
      >
        <div class="flex border-b border-n-weak">
          <button
            type="button"
            class="relative px-4 py-2 text-sm font-medium after:absolute after:bottom-0 after:left-0 after:right-0 after:h-[2px] after:rounded-full after:transition-all after:duration-200"
            :class="
              activeSettingsTab === 'general'
                ? 'text-n-blue-11 after:bg-n-brand after:opacity-100'
                : 'text-n-slate-11 after:bg-transparent after:opacity-0 hover:text-n-slate-12'
            "
            @click="activeSettingsTab = 'general'"
          >
            {{ t('PROSPECTING.SETTINGS.TABS.GENERAL') }}
          </button>
          <button
            type="button"
            class="relative px-4 py-2 text-sm font-medium after:absolute after:bottom-0 after:left-0 after:right-0 after:h-[2px] after:rounded-full after:transition-all after:duration-200"
            :class="
              activeSettingsTab === 'score'
                ? 'text-n-blue-11 after:bg-n-brand after:opacity-100'
                : 'text-n-slate-11 after:bg-transparent after:opacity-0 hover:text-n-slate-12'
            "
            @click="activeSettingsTab = 'score'"
          >
            {{ t('PROSPECTING.SETTINGS.TABS.SCORE') }}
          </button>
        </div>

        <div v-show="activeSettingsTab === 'general'" class="grid gap-4">
          <div class="grid gap-3 md:grid-cols-2">
            <label class="grid gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.FIELDS.CRM_PIPELINE') }}
              </span>
              <ChoiceSelect
                v-model="form.default_crm_pipeline_id"
                :options="pipelineChoices"
                :aria-label="t('PROSPECTING.SETTINGS.FIELDS.CRM_PIPELINE')"
                @change="fetchCrmStages(form.default_crm_pipeline_id)"
              />
            </label>

            <label class="grid gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.FIELDS.CRM_STAGE') }}
              </span>
              <ChoiceSelect
                v-model="form.default_crm_stage_id"
                :options="stageChoices"
                :aria-label="t('PROSPECTING.SETTINGS.FIELDS.CRM_STAGE')"
                :disabled="!crmStages.length"
              />
            </label>
          </div>

          <ProspectingSearchCountryField
            v-model="form.search_country"
            :countries="settings.search_countries || []"
          />

          <div
            class="grid gap-3 rounded-md border border-n-weak bg-n-solid-2 p-3 md:grid-cols-2"
          >
            <div class="grid gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.PLATFORM.KEYS_TITLE') }}
              </span>
              <p
                class="flex items-center gap-2 text-sm"
                :class="keysReady ? 'text-n-teal-11' : 'text-n-amber-11'"
              >
                <span
                  class="size-4 shrink-0"
                  :class="
                    keysReady
                      ? 'i-lucide-circle-check'
                      : 'i-lucide-triangle-alert'
                  "
                />
                {{ keysStatusText }}
              </p>
              <p
                v-if="
                  settings.platform_google_places_configured &&
                  !settings.google_maps_browser_api_key
                "
                class="text-xs text-n-slate-10"
              >
                {{ t('PROSPECTING.SETTINGS.PLATFORM.MAP_KEY_MISSING') }}
              </p>
            </div>
            <div class="grid gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.PLATFORM.RESEARCH_TITLE') }}
              </span>
              <p
                class="flex items-center gap-2 text-sm"
                :class="
                  settings.research_enabled
                    ? 'text-n-teal-11'
                    : 'text-n-slate-11'
                "
              >
                <span
                  class="size-4 shrink-0"
                  :class="
                    settings.research_enabled
                      ? 'i-lucide-circle-check'
                      : 'i-lucide-circle-minus'
                  "
                />
                {{
                  settings.research_enabled
                    ? t('PROSPECTING.SETTINGS.PLATFORM.RESEARCH_ENABLED')
                    : t('PROSPECTING.SETTINGS.PLATFORM.RESEARCH_DISABLED')
                }}
              </p>
            </div>
          </div>

          <ProspectingMockProviderNotice v-if="settings.mock_provider" />

          <ProspectingAiCredentialNotice
            v-if="
              settings.research_enabled && !settings.ai_credential_configured
            "
          />

          <label class="grid gap-1 md:w-1/3">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('PROSPECTING.SETTINGS.FIELDS.CACHE_TTL') }}
            </span>
            <input
              v-model="form.cache_ttl_seconds"
              type="number"
              min="0"
              class="h-10 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
            />
          </label>

          <div
            class="grid gap-3 rounded-md border border-n-weak bg-n-solid-2 p-3 md:grid-cols-2"
          >
            <div>
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.USAGE_DAILY') }}
              </span>
              <p class="text-sm text-n-slate-12">
                {{
                  t('PROSPECTING.SETTINGS.USAGE_OF', {
                    used: settings.usage?.daily_used || 0,
                    limit: t('PROSPECTING.SETTINGS.UNLIMITED'),
                  })
                }}
              </p>
            </div>
            <div>
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.USAGE_MONTHLY') }}
              </span>
              <p class="text-sm text-n-slate-12">
                {{
                  t('PROSPECTING.SETTINGS.USAGE_OF', {
                    used: settings.usage?.monthly_used || 0,
                    limit: t('PROSPECTING.SETTINGS.UNLIMITED'),
                  })
                }}
              </p>
            </div>
          </div>
        </div>

        <div v-show="activeSettingsTab === 'score'" class="grid gap-5">
          <div
            class="rounded-lg border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <div
              class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between"
            >
              <div class="grid gap-1">
                <h2 class="text-base font-semibold text-n-slate-12">
                  {{ t('PROSPECTING.SETTINGS.SCORING_TITLE') }}
                </h2>
                <p class="max-w-2xl text-sm text-n-slate-10">
                  {{ t('PROSPECTING.SETTINGS.SCORING_HINT') }}
                </p>
              </div>
              <span
                class="inline-flex w-fit items-center rounded-full border px-2.5 py-1 text-xs font-semibold"
                :class="
                  isCustomScoringProfile
                    ? 'border-n-amber-5 bg-n-amber-2 text-n-amber-11'
                    : 'border-n-teal-5 bg-n-teal-2 text-n-teal-11'
                "
              >
                {{ scoringProfileBadge }}
              </span>
            </div>

            <div class="mt-4 grid gap-3 md:grid-cols-2">
              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('PROSPECTING.SETTINGS.FIELDS.SEARCH_SCORE_MODE') }}
                </span>
                <ChoiceSelect
                  v-model="form.search_score_mode"
                  :options="searchScoreModeChoices"
                  :aria-label="
                    t('PROSPECTING.SETTINGS.FIELDS.SEARCH_SCORE_MODE')
                  "
                />
              </label>
              <div
                class="rounded-md border border-n-weak bg-n-solid-1 px-3 py-2 text-xs leading-relaxed text-n-slate-10"
              >
                {{
                  form.search_score_mode === 'gbp'
                    ? t('PROSPECTING.SETTINGS.SEARCH_SCORE_MODE_GBP_HINT')
                    : t('PROSPECTING.SETTINGS.SEARCH_SCORE_MODE_GENERAL_HINT')
                }}
              </div>
            </div>

            <label class="mt-4 grid gap-1">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('PROSPECTING.SETTINGS.FIELDS.SCORING_PROFILE') }}
              </span>
              <ChoiceSelect
                v-model="form.scoring_profile_option"
                :options="scoringProfileChoices"
                :aria-label="t('PROSPECTING.SETTINGS.FIELDS.SCORING_PROFILE')"
              />
            </label>
          </div>

          <ProspectingOrthScoreWeights
            v-if="isOrthEngine"
            :weights="orthScoringWeights || {}"
            :mode="form.search_score_mode"
            :is-custom="isCustomScoringProfile"
          />
          <div
            v-else
            class="overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <div class="border-b border-n-weak px-4 py-3">
              <h3 class="text-sm font-semibold text-n-slate-12">
                {{ t('PROSPECTING.SETTINGS.SCORING_WEIGHTS_TITLE') }}
              </h3>
              <p class="text-xs text-n-slate-10">
                {{
                  isCustomScoringProfile
                    ? t('PROSPECTING.SETTINGS.SCORING_CUSTOM_HINT')
                    : t('PROSPECTING.SETTINGS.SCORING_PROFILE_HINT')
                }}
              </p>
            </div>

            <div
              v-for="key in scoringWeightKeys"
              :key="key"
              class="grid items-center gap-3 px-4 py-3 md:grid-cols-[160px_1fr_90px]"
              :class="{
                'border-b border-n-weak':
                  key !== scoringWeightKeys[scoringWeightKeys.length - 1],
              }"
            >
              <label class="text-sm font-medium text-n-slate-11">
                {{ t(`PROSPECTING.SETTINGS.SCORING_WEIGHTS.${key}`) }}
              </label>
              <div class="h-2 overflow-hidden rounded-full bg-n-solid-3">
                <div
                  class="h-full rounded-full bg-gradient-to-r from-n-blue-9 to-n-teal-9"
                  :style="{ width: `${weightPercent(key)}%` }"
                />
              </div>
              <input
                v-if="isCustomScoringProfile"
                v-model="form.custom_scoring_weights[key]"
                type="number"
                min="0"
                max="100"
                class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-center text-sm text-n-slate-12"
              />
              <div
                v-else
                class="flex h-9 items-center justify-center rounded-md border border-n-weak bg-n-solid-3 text-sm font-semibold text-n-slate-10"
              >
                {{ displayedScoringWeights[key] || 0 }}
              </div>
            </div>
          </div>
        </div>

        <button
          type="submit"
          class="h-10 w-fit rounded-md bg-n-brand px-4 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="isSaving"
        >
          {{
            isSaving
              ? t('PROSPECTING.SETTINGS.SAVING')
              : t('PROSPECTING.SETTINGS.SAVE')
          }}
        </button>
      </form>
    </section>
  </main>
</template>
