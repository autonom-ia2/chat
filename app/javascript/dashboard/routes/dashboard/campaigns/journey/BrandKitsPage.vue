<script setup>
// Campanhas › Campanha › Identidade visual (#1076): the logo, colors and fonts the e-mails use.
// A tab of Campanha (the menu keeps "Campanha" lit). Empty: one sentence and "Usar o meu site".
// The same page holds Nova identidade and Alterar (BrandKitEditor) and the archived list.
// `?from=campaign` came from Nova campanha (Gerenciar): a button takes the person back.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignTabs from 'dashboard/components-next/CampaignJourney/CampaignTabs.vue';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import BrandKitCard from 'dashboard/components-next/BrandKits/BrandKitCard.vue';
import BrandKitEditor from 'dashboard/components-next/BrandKits/BrandKitEditor.vue';
import { useBrandKits } from 'dashboard/components-next/BrandKits/useBrandKits';
import BrandKitsAPI from 'dashboard/api/brandKits';

const NS = 'BRAND_KITS.PAGE';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const globalConfig = useMapGetter('globalConfig/get');
const { kits, archivedCount, loaded, canManage, fetchKits } = useBrandKits();

const archived = ref([]);
const busyId = ref(null);
const hasLoadError = ref(false);

const editing = computed(() => {
  if (route.name === 'campaigns_journey_brand_kit_new') return 'new';
  if (route.name === 'campaigns_journey_brand_kit_edit') return 'edit';
  return null;
});
const showArchived = computed(() => route.query.archived === '1');
const fromCampaign = computed(() => route.query.from === 'campaign');
const keptQuery = computed(() =>
  fromCampaign.value ? { from: 'campaign' } : {}
);

const loadArchived = async () => {
  const { data } = await BrandKitsAPI.list({ archived: true });
  archived.value = data.payload || [];
};

const load = async () => {
  hasLoadError.value = false;
  try {
    await fetchKits();
    if (showArchived.value) await loadArchived();
  } catch {
    hasLoadError.value = true;
  }
};

const goList = (query = {}) =>
  router.push({
    name: 'campaigns_journey_brand_kits',
    query: { ...keptQuery.value, ...query },
  });
const startNew = () =>
  router.push({
    name: 'campaigns_journey_brand_kit_new',
    query: keptQuery.value,
  });
const edit = kit =>
  router.push({
    name: 'campaigns_journey_brand_kit_edit',
    params: { kitId: kit.id },
    query: keptQuery.value,
  });

const backToCampaign = () =>
  router.push({ name: 'campaigns_journey_new', query: { returned: '1' } });
const createEmail = () =>
  router.push(
    globalConfig.value?.campaignImportEnabled
      ? { name: 'campaigns_journey_new' }
      : { name: 'campaigns_journey_index' }
  );

const onSaved = ({ kit, created }) => {
  goList(created ? { saved: '1' } : {});
  if (!created) useAlert(t(`${NS}.UPDATED`, { name: kit.name }));
};

const run = async (kit, action, message) => {
  busyId.value = kit.id;
  try {
    await action(kit.id);
    await fetchKits();
    if (showArchived.value) await loadArchived();
    useAlert(message);
  } catch {
    useAlert(t(`${NS}.ACTION_ERROR`));
  } finally {
    busyId.value = null;
  }
};

const makeDefault = kit =>
  run(
    kit,
    BrandKitsAPI.setDefault,
    t(`${NS}.DEFAULT_CHANGED`, { name: kit.name })
  );
const archive = kit =>
  run(kit, BrandKitsAPI.archive, t(`${NS}.ARCHIVED_DONE`, { name: kit.name }));
const restore = kit =>
  run(kit, BrandKitsAPI.restore, t(`${NS}.RESTORED`, { name: kit.name }));

const toggleArchived = async () => {
  await goList(showArchived.value ? {} : { archived: '1' });
  if (route.query.archived === '1') await loadArchived();
};

useOnEnter(load);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t(`${NS}.BREADCRUMB`)"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t('BRAND_KITS.TABS.IDENTITY') }}
        </span>
      </nav>
      <CampaignTabs active="identity" />

      <div
        v-if="fromCampaign && !editing"
        class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-5 py-3"
      >
        <p class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.FROM_CAMPAIGN`) }}
        </p>
        <Button
          :label="t(`${NS}.BACK_TO_CAMPAIGN`)"
          icon="i-lucide-arrow-left"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          data-test="back-to-campaign"
          @click="backToCampaign"
        />
      </div>

      <BrandKitEditor
        v-if="editing"
        :kit-id="editing === 'edit' ? route.params.kitId : null"
        @saved="onSaved"
        @cancel="goList()"
      />

      <template v-else>
        <div
          v-if="route.query.saved === '1'"
          role="status"
          class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-n-teal-11 px-5 py-3 text-white"
          data-test="saved-banner"
        >
          <p class="m-0 flex items-center gap-2 text-sm">
            <span class="i-lucide-check size-4" aria-hidden="true" />
            {{ t(`${NS}.SAVED`) }}
          </p>
          <Button
            :label="
              fromCampaign
                ? t(`${NS}.BACK_TO_CAMPAIGN`)
                : t(`${NS}.CREATE_EMAIL`)
            "
            icon="i-lucide-arrow-right"
            trailing-icon
            variant="outline"
            color="slate"
            class="!min-h-11 !rounded-xl !bg-white"
            @click="fromCampaign ? backToCampaign() : createEmail()"
          />
        </div>

        <div v-if="!loaded && !hasLoadError" class="flex justify-center p-12">
          <Spinner />
        </div>
        <p
          v-else-if="hasLoadError"
          role="alert"
          class="m-0 rounded-2xl border border-n-weak bg-n-solid-1 p-6 text-sm text-n-ruby-11"
        >
          {{ t(`${NS}.LOAD_ERROR`) }}
        </p>

        <section
          v-else-if="!kits.length && !showArchived"
          class="relative overflow-hidden rounded-3xl bg-[#0D2344] px-6 py-10 text-white sm:px-11"
          data-test="empty-state"
        >
          <p
            class="m-0 flex items-center gap-2 text-sm font-semibold text-n-blue-8"
          >
            <span class="i-lucide-palette size-4" aria-hidden="true" />
            {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
          </p>
          <h1 class="mb-0 mt-3 text-3xl font-bold tracking-tight text-white">
            {{ t('BRAND_KITS.TABS.IDENTITY') }}
          </h1>
          <p class="mb-0 mt-3 max-w-xl text-base text-white/80">
            {{ t(`${NS}.EMPTY`) }}
          </p>
          <Button
            v-if="canManage"
            :label="t(`${NS}.USE_MY_SITE`)"
            icon="i-lucide-globe"
            variant="outline"
            color="slate"
            class="mt-6 !min-h-11 !rounded-xl !bg-white !text-n-slate-12"
            data-test="use-my-site"
            @click="startNew"
          />
          <p v-if="archivedCount" class="mb-0 mt-6 text-sm text-white/80">
            {{ t(`${NS}.ARCHIVED_COUNT`, { count: archivedCount }) }}
            <button
              type="button"
              class="min-h-11 px-1 font-semibold text-white underline"
              @click="toggleArchived"
            >
              {{ t(`${NS}.SEE_ARCHIVED`) }}
            </button>
          </p>
        </section>

        <template v-else>
          <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
            <div class="min-w-0">
              <h1
                class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
              >
                {{
                  showArchived
                    ? t(`${NS}.ARCHIVED_TITLE`)
                    : t('BRAND_KITS.TABS.IDENTITY')
                }}
              </h1>
              <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
                {{
                  showArchived
                    ? t(`${NS}.ARCHIVED_SUBTITLE`)
                    : t(`${NS}.SUBTITLE`)
                }}
              </p>
            </div>
            <Button
              v-if="canManage && !showArchived"
              :label="t(`${NS}.NEW`)"
              icon="i-lucide-plus"
              class="!min-h-11 !rounded-xl"
              data-test="new-kit"
              @click="startNew"
            />
          </header>
          <div class="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            <BrandKitCard
              v-for="kit in showArchived ? archived : kits"
              :key="kit.id"
              :kit="kit"
              :can-manage="canManage"
              :busy="busyId === kit.id"
              @edit="edit"
              @make-default="makeDefault"
              @archive="archive"
              @restore="restore"
            />
          </div>
          <p
            v-if="showArchived && !archived.length"
            class="m-0 text-sm text-n-slate-11"
          >
            {{ t(`${NS}.ARCHIVED_EMPTY`) }}
          </p>
          <p
            v-if="archivedCount || showArchived"
            class="mb-0 mt-5 flex items-center gap-2 text-sm text-n-slate-11"
          >
            <span class="i-lucide-archive size-4" aria-hidden="true" />
            <template v-if="!showArchived">
              {{ t(`${NS}.ARCHIVED_COUNT`, { count: archivedCount }) }}
            </template>
            <button
              type="button"
              class="min-h-11 px-1 font-semibold text-n-blue-11 hover:underline"
              data-test="toggle-archived"
              @click="toggleArchived"
            >
              {{
                showArchived ? t(`${NS}.BACK_TO_LIST`) : t(`${NS}.SEE_ARCHIVED`)
              }}
            </button>
          </p>
        </template>
      </template>
    </div>
  </section>
</template>
