<script setup>
// "Público" (#993, PRD §6.6): the lists of people imported for campaigns, over the
// existing campaign_imports API. "Novo público" opens its own page (NewAudiencePage);
// "Usar em nova campanha" opens Passo 1 with the audience selected (F3); "Excluir público"
// deletes only the list (F2) and says which campaigns still use it (audience_in_use).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import { toLocaleTag } from 'dashboard/components-next/CampaignJourney/localeTag';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AudienceSidePanel from 'dashboard/components-next/CampaignJourney/AudienceSidePanel.vue';
import AudienceChannelBadges from 'dashboard/components-next/CampaignJourney/AudienceChannelBadges.vue';
import { buildAudienceRow } from 'dashboard/components-next/CampaignJourney/audienceRows';
import { campaignsUsingAudience } from 'dashboard/components-next/CampaignJourney/journeyErrors';
import { LEGACY_QUERY } from 'dashboard/components-next/CampaignJourney/campaignChannels';

const NS = 'CAMPAIGN_JOURNEY.AUDIENCES';

const { t, n, locale } = useI18n();
const store = useStore();
const router = useRouter();
const canManage = useCanManage('campaign_manage');

const campaignImports = useMapGetter('campaignImports/getCampaignImports');
const uiFlags = useMapGetter('campaignImports/getUIFlags');
const meta = useMapGetter('campaignImports/getMeta');

const deleteDialogRef = ref(null);
const deleting = ref(null);
// Side panel (PRD §6.6): the audience whose details are open.
const openAudienceId = ref(null);
const hasLoadError = ref(false);

const rows = computed(() =>
  (campaignImports.value || []).map(buildAudienceRow)
);
const isLoading = computed(() => uiFlags.value?.isFetching);
const savedCount = computed(() => meta.value?.count || rows.value.length);
const peopleOnPage = computed(() =>
  rows.value.reduce((total, row) => total + row.people, 0)
);

const formatDate = value =>
  value
    ? new Date(value).toLocaleDateString(toLocaleTag(locale.value), { dateStyle: 'short' })
    : '';

const fetchAudiences = async () => {
  hasLoadError.value = false;
  try {
    await store.dispatch('campaignImports/get');
  } catch {
    hasLoadError.value = true;
  }
};

const openNewAudience = () =>
  router.push({ name: 'campaigns_journey_audience_new' });

const useInCampaign = row =>
  router.push({
    name: 'campaigns_journey_new',
    query: { audience: String(row.id) },
  });

const askDelete = row => {
  deleting.value = row;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  const row = deleting.value;
  deleteDialogRef.value?.close();
  try {
    await store.dispatch('campaignImports/delete', row.id);
    if (openAudienceId.value === row.id) openAudienceId.value = null;
    useAlert(t(`${NS}.DELETED`));
  } catch (error) {
    const campaigns = campaignsUsingAudience(error);
    useAlert(
      campaigns.length
        ? t(`${NS}.IN_USE`, { campaigns: campaigns.join(', ') })
        : t(`${NS}.ERROR`)
    );
  }
};

useOnEnter(fetchAudiences);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t('CAMPAIGN_JOURNEY.LIST.BREADCRUMB')"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t('CAMPAIGN_JOURNEY.SIDEBAR.AUDIENCES') }}
        </span>
      </nav>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1
            class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ t(`${NS}.TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${NS}.SUBTITLE`) }}
          </p>
        </div>
        <Button
          v-if="canManage"
          :label="t(`${NS}.NEW_AUDIENCE`)"
          icon="i-lucide-plus"
          class="!min-h-11 !rounded-xl"
          data-test="new-audience"
          @click="openNewAudience"
        />
      </header>

      <section
        class="mb-7 flex flex-col overflow-hidden rounded-3xl border border-n-weak bg-n-solid-1 shadow-sm sm:flex-row"
        :aria-label="t(`${NS}.OVERVIEW`)"
      >
        <div class="min-w-0 bg-[#0D2344] px-6 py-6 text-white sm:w-[32%]">
          <p class="mb-0 text-xs text-white opacity-80">
            {{ t(`${NS}.SAVED`) }}
          </p>
          <p class="mb-0 mt-2 text-3xl font-semibold tabular-nums">
            {{ n(savedCount) }}
          </p>
        </div>
        <div class="min-w-0 flex-1 px-6 py-6 md:px-8">
          <p class="mb-0 text-xs text-n-slate-11">{{ t(`${NS}.PEOPLE`) }}</p>
          <p
            class="mb-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
          >
            {{ n(peopleOnPage) }}
          </p>
        </div>
      </section>

      <section class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm">
        <p
          v-if="hasLoadError"
          role="alert"
          class="m-0 border-b border-n-weak px-6 py-3 text-sm text-n-ruby-11"
        >
          {{ t(`${NS}.LOAD_ERROR`) }}
        </p>
        <div v-if="isLoading && !rows.length" class="flex justify-center p-12">
          <Spinner />
        </div>
        <div
          v-else-if="!rows.length"
          class="flex flex-col items-center gap-3 p-12 text-center"
          data-test="audiences-empty"
        >
          <span
            class="i-lucide-users size-8 text-n-slate-9"
            aria-hidden="true"
          />
          <p class="mb-0 font-medium text-n-slate-12">
            {{ t(`${NS}.EMPTY_TITLE`) }}
          </p>
          <p class="mb-0 max-w-md text-sm text-n-slate-11">
            {{ t(`${NS}.EMPTY_SUBTITLE`) }}
          </p>
          <Button
            v-if="canManage"
            :label="t(`${NS}.NEW_AUDIENCE`)"
            icon="i-lucide-plus"
            class="!min-h-11 !rounded-xl"
            @click="openNewAudience"
          />
        </div>
        <ul v-else class="m-0 list-none p-0">
          <li
            v-for="row in rows"
            :key="row.id"
            :data-audience="row.id"
            class="grid gap-3 border-b border-n-weak px-4 py-4 last:border-0 lg:grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_8rem_8rem_auto] md:items-center xl:px-6"
          >
            <div class="min-w-0">
              <button
                type="button"
                class="m-0 min-h-11 max-w-full truncate rounded-lg p-0 text-start text-sm font-semibold text-n-slate-12 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                :aria-label="t(`${NS}.PANEL.OPEN_ARIA`, { name: row.name })"
                :data-open-panel="row.id"
                @click="openAudienceId = row.id"
              >
                {{ row.name }}
              </button>
              <p class="mb-0 truncate text-xs text-n-slate-11">
                {{ row.sourceFilename }}
              </p>
            </div>
            <AudienceChannelBadges :badges="row.badges" />
            <p class="mb-0 text-sm text-n-slate-12">
              {{
                t(`${NS}.PEOPLE_COUNT`, { count: n(row.people) }, row.people)
              }}
            </p>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ formatDate(row.createdAt) }}
            </p>
            <div class="flex flex-wrap items-center gap-1">
            <Button
              v-if="canManage && row.isSaved"
              :label="t(`${NS}.USE_IN_CAMPAIGN`)"
              :aria-label="t(`${NS}.USE_IN_CAMPAIGN_ARIA`, { name: row.name })"
              variant="ghost"
              size="sm"
              class="!min-h-11"
              :data-use="row.id"
              @click="useInCampaign(row)"
            />
            <Button
              v-if="canManage && row.canDelete"
              icon="i-lucide-trash-2"
              :aria-label="t(`${NS}.DELETE_ARIA`, { name: row.name })"
              variant="ghost"
              color="ruby"
              size="sm"
              class="!min-h-11 !min-w-11"
              :data-delete="row.id"
              @click="askDelete(row)"
            />
            <router-link
              :to="{
                name: 'contacts_campaign_imports',
                query: { [LEGACY_QUERY]: '1' },
              }"
              class="flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-label="t(`${NS}.DETAILS_ARIA`, { name: row.name })"
            >
              {{ t(`${NS}.DETAILS`) }}
              <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
            </router-link>
            </div>
          </li>
        </ul>
      </section>
    </div>
    <AudienceSidePanel
      v-if="openAudienceId"
      :audience-id="openAudienceId"
      :can-manage="canManage"
      @close="openAudienceId = null"
      @use="useInCampaign"
      @delete="askDelete"
    />
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t(`${NS}.CONFIRM_TITLE`, { name: deleting?.name || '' })"
      :description="t(`${NS}.CONFIRM_TEXT`)"
      :confirm-button-label="t(`${NS}.CONFIRM`)"
      @confirm="confirmDelete"
    />
  </section>
</template>
