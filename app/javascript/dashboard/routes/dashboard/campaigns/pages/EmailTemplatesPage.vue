<script setup>
import {
  computed,
  watch,
  onActivated,
  onMounted,
  onBeforeUnmount,
  ref,
  nextTick,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';
import EmailCampaignTemplateImportsAPI from 'dashboard/api/emailCampaignTemplateImports';
import {
  compileEmailMjml,
  disposeEmailMjmlCompiler,
} from 'dashboard/helper/compileEmailMjml';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';
import { buildTemplateCampaignPayload } from './emailTemplateBody';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const canManage = useCanManage('campaign_manage');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
// "Trazer meu modelo" (#1099): só com a flag email_template_import e quem gerencia campanhas.
const canImport = computed(
  () =>
    canManage.value &&
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.EMAIL_TEMPLATE_IMPORT
    )
);
const IMPORT = 'EMAIL_IMPORT.SCREEN.LIBRARY';
// The model just brought in (#1099): marked "Novo" for this visit only — the address loses ?novo=
// right away, so reloading or coming back does not announce it again.
const newTemplateId = ref(null);
const pendingImport = ref(null);

const campaignId = computed(() => {
  const id = Number(route.params.campaignId);
  return Number.isNaN(id) ? null : id;
});

const templates = ref([]);
const thumbHtml = ref({});
const isLoading = ref(true);
const isApplying = ref(false);
const activeCategory = ref('all');
const previewTemplate = ref(null);
const previewHtml = ref('');
const isPreviewLoading = ref(false);

// Lazy-thumbnail plumbing: observe card roots and fetch body_html only when visible.
const cardEls = new Map();
const inFlightThumbs = new Set();
let thumbObserver = null;
let isUnmounted = false;
let mounted = false;
// Monotonic token so a slow preview fetch can't overwrite a newer one.
let previewSeq = 0;

const UX = 'CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE';
const library = ref('global');
const search = ref('');
const previewDevice = ref('desktop');
const previewDialog = ref(null);
const newTemplate = ref(null);
const displayName = template =>
  template.catalog_key
    ? t(`${UX}.MODELS.${template.catalog_key}`)
    : template.name;
const libraryTemplates = computed(() =>
  templates.value.filter(item =>
    library.value === 'global'
      ? item.account_id === null
      : item.account_id !== null
  )
);
const categoryLabel = category => {
  if (category === 'all') {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.ALL_CATEGORIES');
  }
  if (category === 'meus-modelos') return t(`${UX}.MY_MODELS`);
  return t(`CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.CATEGORIES.${category}`, category);
};

const categories = computed(() => {
  const unique = new Set(
    templates.value
      .filter(item =>
        library.value === 'global'
          ? item.account_id === null
          : item.account_id !== null
      )
      .map(item => item.category)
      .filter(Boolean)
  );
  return ['all', ...Array.from(unique).sort()];
});

const filteredTemplates = computed(() => {
  const query = search.value.trim().toLocaleLowerCase();
  const found = libraryTemplates.value.filter(
    item =>
      (activeCategory.value === 'all' ||
        item.category === activeCategory.value) &&
      [displayName(item), categoryLabel(item.category)].some(value =>
        value?.toLocaleLowerCase().includes(query)
      )
  );
  // The model just brought in comes first, marked "Novo".
  return [
    ...found.filter(item => item.id === newTemplateId.value),
    ...found.filter(item => item.id !== newTemplateId.value),
  ];
});
const showImportEmpty = computed(
  () =>
    canImport.value &&
    library.value === 'own' &&
    !libraryTemplates.value.length &&
    !search.value.trim()
);
// The body of a template as HTML: compiled when saved, or compiled here from its MJML (an imported
// model keeps only the MJML the server checked).
const bodyHtmlOf = async template =>
  template.body_html || compileEmailMjml(template.body_mjml);
const fetchTemplates = async () => {
  isLoading.value = true;
  try {
    const { data } = await EmailCampaignTemplatesAPI.index();
    templates.value = Array.isArray(data) ? data : data.payload || [];
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// The index payload is lightweight (no body_html); fetch each template's compiled
// HTML lazily (only when its card scrolls into view) so the gallery cards can render
// a real scaled visual preview without an N-request burst on mount.
const fetchThumbnail = async id => {
  // Fetch-once: skip if already cached or a request is already in flight.
  if (thumbHtml.value[id] !== undefined || inFlightThumbs.has(id)) return;
  inFlightThumbs.add(id);
  try {
    const { data } = await EmailCampaignTemplatesAPI.show(id);
    const html = await bodyHtmlOf(data);
    if (isUnmounted) return;
    thumbHtml.value = { ...thumbHtml.value, [id]: html };
  } catch (error) {
    if (isUnmounted) return;
    thumbHtml.value = { ...thumbHtml.value, [id]: '' };
  } finally {
    inFlightThumbs.delete(id);
  }
};

// Template ref callback: track each card root so the observer can watch it.
const registerCard = (id, el) => {
  if (el) {
    cardEls.set(id, el);
    if (thumbObserver) thumbObserver.observe(el);
  } else {
    const prev = cardEls.get(id);
    if (prev && thumbObserver) thumbObserver.unobserve(prev);
    cardEls.delete(id);
  }
};

const goToBuilder = () => {
  if (!campaignId.value) return;
  router.push({
    name: 'campaigns_email_builder',
    params: {
      accountId: route.params.accountId,
      campaignId: campaignId.value,
    },
  });
};

const goToImport = importId => {
  router.push({
    name: 'campaigns_email_template_import',
    params: { accountId: route.params.accountId, importId },
    query: campaignId.value ? { campaign: campaignId.value } : {},
  });
};

const fetchPendingImport = async () => {
  if (!canImport.value) return;
  try {
    const { data } = await EmailCampaignTemplateImportsAPI.latest();
    pendingImport.value = data?.payload?.[0] || null;
  } catch (error) {
    pendingImport.value = null;
  }
};

const goBack = () => {
  if (campaignId.value) {
    goToBuilder();
    return;
  }
  router.push({
    name: 'campaigns_email_index',
    params: { accountId: route.params.accountId },
  });
};

const openPreview = async template => {
  previewTemplate.value = template;
  previewDevice.value = 'desktop';
  await nextTick();
  previewDialog.value.open();
  previewHtml.value = '';
  // The gallery index payload is lightweight (no body); fetch the full template so we can
  // render its compiled HTML. body_html is compiled at seed time; fall back gracefully if absent.
  isPreviewLoading.value = true;
  // Race guard: capture a token; only the latest open may apply its response.
  previewSeq += 1;
  const requestSeq = previewSeq;
  try {
    const { data } = await EmailCampaignTemplatesAPI.show(template.id);
    const html = await bodyHtmlOf(data);
    if (isUnmounted || requestSeq !== previewSeq) return;
    previewHtml.value = html;
  } catch (error) {
    if (isUnmounted || requestSeq !== previewSeq) return;
    previewHtml.value = '';
  } finally {
    if (!isUnmounted && requestSeq === previewSeq) {
      isPreviewLoading.value = false;
    }
  }
};

const closePreview = () => {
  previewTemplate.value = null;
  previewHtml.value = '';
  isPreviewLoading.value = false;
};

const useTemplate = async template => {
  isApplying.value = true;
  try {
    const { data } = await EmailCampaignTemplatesAPI.show(template.id);
    const campaignPayload = buildTemplateCampaignPayload(data);

    if (!campaignPayload) {
      useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.MISSING_BODY'));
      return;
    }

    if (campaignId.value) {
      await store.dispatch('emailCampaigns/update', {
        id: campaignId.value,
        ...campaignPayload,
      });
      useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.APPLIED'));
      goToBuilder();
    } else {
      newTemplate.value = { ...campaignPayload, name: displayName(template) };
    }
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.APPLY_ERROR'));
  } finally {
    isApplying.value = false;
    if (previewTemplate.value) previewDialog.value.close();
  }
};

onMounted(async () => {
  thumbObserver = new IntersectionObserver(
    entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        const id = Number(entry.target.dataset.templateId);
        fetchThumbnail(id);
        thumbObserver.unobserve(entry.target);
      });
    },
    { rootMargin: '200px' }
  );
  // Observe any cards already registered before the observer existed.
  cardEls.forEach(el => thumbObserver.observe(el));

  try {
    if (campaignId.value) {
      await store.dispatch('emailCampaigns/getOne', campaignId.value);
    } else {
      await Promise.all([
        store.dispatch('emailSenderIdentities/get'),
        store.dispatch('inboxes/get'),
      ]);
    }
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.LOAD_ERROR'));
  }
  await fetchTemplates();
  fetchPendingImport();
  mounted = true;
});
onActivated(() => {
  if (!mounted) return;
  fetchTemplates();
  fetchPendingImport();
});

onBeforeUnmount(() => {
  isUnmounted = true;
  if (thumbObserver) {
    thumbObserver.disconnect();
    thumbObserver = null;
  }
  cardEls.clear();
  disposeEmailMjmlCompiler();
});

// Back from "Trazer meu modelo" with the saved model: "Meus modelos", the card marked "Novo" and the
// confirmation (the page is kept alive, so this also runs when it is shown again).
watch(
  () => route.query.novo,
  novo => {
    const id = Number(novo) || null;
    if (!id) return;
    newTemplateId.value = id;
    library.value = 'own';
    activeCategory.value = 'all';
    useAlert(t(`${IMPORT}.SAVED`));
    const query = Object.fromEntries(
      Object.entries(route.query).filter(([key]) => key !== 'novo')
    );
    router.replace({ name: route.name, params: route.params, query });
  },
  { immediate: true }
);

const chooseLibrary = value => {
  library.value = value;
  activeCategory.value = 'all';
  search.value = '';
};
</script>

<template>
  <section
    class="flex h-full min-w-0 flex-1 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-5 lg:p-8">
      <p class="mb-5 flex items-center gap-2 text-xs text-n-slate-11">
        <button class="min-h-9" @click="goBack">
          {{ t(`${UX}.CAMPAIGNS`) }}
        </button>
        <span class="i-lucide-chevron-right size-3.5" />
        {{ t(`${UX}.LIBRARY_BUTTON`) }}
      </p>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1
            class="mb-0 text-[1.75rem] font-semibold tracking-tight text-n-slate-12"
          >
            {{ t(`${UX}.LIBRARY_TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${UX}.LIBRARY_SUBTITLE`) }}
          </p>
        </div>
        <div class="relative flex flex-wrap gap-2">
          <Button
            v-if="canImport"
            :label="t(`${IMPORT}.BUTTON`)"
            icon="i-lucide-upload"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            @click="goToImport()"
          />
          <Button
            :label="t(`${UX}.${campaignId ? 'BACK_EDITOR' : 'BACK_CAMPAIGNS'}`)"
            icon="i-lucide-arrow-left"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            @click="goBack"
          />
          <EmailCampaignDialog
            v-if="newTemplate"
            :template="newTemplate"
            @saved="newTemplate = null"
            @close="newTemplate = null"
          />
        </div>
      </header>
      <div class="mb-5 flex flex-wrap items-center justify-between gap-4">
        <nav
          class="flex gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1"
          :aria-label="t(`${UX}.LIBRARY_TITLE`)"
        >
          <button
            v-for="option in ['global', 'own']"
            :key="option"
            class="flex min-h-11 items-center gap-2 rounded-lg px-4 text-sm font-medium"
            :class="
              library === option
                ? 'bg-n-blue-3 text-n-blue-11'
                : 'text-n-slate-11'
            "
            :aria-pressed="library === option"
            @click="chooseLibrary(option)"
          >
            <span
              class="size-4"
              :class="
                option === 'global'
                  ? 'i-lucide-layout-template'
                  : 'i-lucide-bookmark'
              "
            />
            {{ t(`${UX}.${option === 'global' ? 'LIBRARY' : 'MY_MODELS'}`) }}
          </button>
        </nav>
        <label
          class="flex min-h-11 w-full items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-3 sm:w-64"
        >
          <span class="i-lucide-search size-4 shrink-0 text-n-slate-11" />
          <input
            v-model="search"
            type="search"
            :aria-label="t(`${UX}.SEARCH_MODEL`)"
            :placeholder="t(`${UX}.SEARCH_MODEL`)"
            class="m-0 min-w-0 w-full !border-0 !bg-transparent !p-0 text-sm !shadow-none !outline-none focus:!ring-0"
          />
        </label>
      </div>
      <nav class="mb-6 flex flex-wrap gap-2" :aria-label="t(`${UX}.PURPOSE`)">
        <button
          v-for="category in categories"
          :key="category"
          class="min-h-11 rounded-full border px-4 text-xs font-medium"
          :class="
            activeCategory === category
              ? 'border-n-brand bg-n-brand text-white'
              : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-1'
          "
          :aria-pressed="activeCategory === category"
          @click="activeCategory = category"
        >
          {{ categoryLabel(category) }}
        </button>
      </nav>
      <div
        v-if="pendingImport"
        class="mb-5 flex flex-wrap items-center gap-3 rounded-2xl border border-n-blue-5 bg-n-blue-2 p-4"
        role="status"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-upload size-5" />
        </span>
        <p class="mb-0 min-w-0 flex-1 text-sm font-medium text-n-slate-12">
          {{
            t(
              `${IMPORT}.${pendingImport.status === 'ready' ? 'READY_TITLE' : 'WAITING_TITLE'}`
            )
          }}
        </p>
        <Button
          :label="t(`${IMPORT}.RESUME`)"
          icon="i-lucide-arrow-right"
          trailing-icon
          class="!min-h-11 !rounded-xl"
          @click="goToImport(pendingImport.id)"
        />
      </div>
      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <div
        v-else-if="showImportEmpty"
        class="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-n-strong bg-n-solid-1 px-6 py-12 text-center"
      >
        <span
          class="mb-2 flex size-16 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-upload size-7" />
        </span>
        <h2 class="mb-0 text-xl font-semibold text-n-slate-12">
          {{ t(`${IMPORT}.EMPTY_TITLE`) }}
        </h2>
        <p class="mb-0 text-base text-n-slate-11">
          {{ t(`${IMPORT}.EMPTY_TEXT`) }}
        </p>
        <Button
          :label="t(`${IMPORT}.BUTTON`)"
          icon="i-lucide-upload"
          size="lg"
          class="mt-2 !min-h-12 !rounded-xl"
          @click="goToImport()"
        />
        <p class="mb-0 mt-1 text-xs text-n-slate-11">
          {{ t(`${IMPORT}.EMPTY_HINT`) }}
        </p>
      </div>
      <p
        v-else-if="!filteredTemplates.length"
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-12 text-center text-sm text-n-slate-11"
      >
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.EMPTY') }}
      </p>
      <div v-else class="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="template in filteredTemplates"
          :key="template.id"
          :ref="el => registerCard(template.id, el)"
          :data-template-id="template.id"
          class="flex min-w-0 flex-col overflow-hidden rounded-2xl border bg-n-solid-1 shadow-sm"
          :class="
            template.id === newTemplateId
              ? 'border-n-brand ring-2 ring-n-brand'
              : 'border-n-weak'
          "
        >
          <button
            class="relative flex h-56 items-center justify-center overflow-hidden border-b border-n-weak bg-n-alpha-1 p-4"
            :aria-label="
              t(`${UX}.PREVIEW_MODEL`, { name: displayName(template) })
            "
            @click="openPreview(template)"
          >
            <img
              v-if="template.thumbnail_url"
              :src="template.thumbnail_url"
              :alt="displayName(template)"
              class="h-full w-full rounded-xl object-cover"
            />
            <div
              v-else-if="thumbHtml[template.id]"
              class="relative h-full w-full overflow-hidden rounded-xl border border-n-weak bg-white"
            >
              <iframe
                :srcdoc="thumbHtml[template.id]"
                :title="displayName(template)"
                sandbox=""
                referrerpolicy="no-referrer"
                scrolling="no"
                tabindex="-1"
                aria-hidden="true"
                loading="lazy"
                class="pointer-events-none h-[56rem] w-[37.5rem] origin-top-left scale-50 border-0"
              />
            </div>
            <Spinner v-else-if="thumbHtml[template.id] === undefined" />
            <span v-else class="i-lucide-image size-8 text-n-slate-9" />
          </button>
          <div class="flex flex-1 flex-col gap-2 p-5">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="w-fit rounded-full bg-n-blue-3 px-2.5 py-1 text-xs font-medium text-n-blue-11"
              >
                {{ categoryLabel(template.category) }}
              </span>
              <span
                v-if="template.id === newTemplateId"
                class="w-fit rounded-full bg-n-brand px-2.5 py-1 text-xs font-semibold text-white"
              >
                {{ t(`${IMPORT}.NEW_BADGE`) }}
              </span>
            </div>
            <h2
              class="mb-0 mt-1 text-base font-semibold leading-6 text-n-slate-12"
            >
              {{ displayName(template) }}
            </h2>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{
                template.id === newTemplateId
                  ? t(`${IMPORT}.NEW_HINT`)
                  : t(`${UX}.MODEL_HINT`)
              }}
            </p>
            <div class="mt-auto flex flex-wrap gap-2 pt-3">
              <Button
                :label="t(`${UX}.PREVIEW`)"
                icon="i-lucide-eye"
                slate
                outline
                class="!min-h-11 flex-1 !rounded-xl"
                @click="openPreview(template)"
              />
              <Button
                v-if="canManage"
                :label="t(`${UX}.USE_MODEL`)"
                icon="i-lucide-arrow-right"
                trailing-icon
                class="!min-h-11 flex-1 !rounded-xl"
                :is-loading="isApplying"
                @click="useTemplate(template)"
              />
            </div>
          </div>
        </article>
      </div>
      <p class="mb-0 mt-6 text-xs text-n-slate-11">
        {{ t(`${UX}.LIBRARY_COUNT`, { count: filteredTemplates.length }) }}
      </p>
    </div>
    <Dialog
      v-if="previewTemplate"
      ref="previewDialog"
      :title="displayName(previewTemplate)"
      type="edit"
      width="3xl"
      :confirm-button-label="t(`${UX}.USE_MODEL`)"
      :show-confirm-button="canManage"
      :is-loading="isApplying"
      overflow-y-auto
      @confirm="useTemplate(previewTemplate)"
      @close="closePreview"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <p class="mb-0 text-xs text-n-slate-11">
          {{ categoryLabel(previewTemplate.category) }}
        </p>
        <div class="flex gap-1 rounded-lg bg-n-alpha-1 p-1">
          <Button
            v-for="option in ['desktop', 'mobile']"
            :key="option"
            type="button"
            :label="t(`${UX}.DEVICES.${option}`)"
            slate
            :variant="previewDevice === option ? 'solid' : 'ghost'"
            class="!min-h-11"
            :aria-pressed="previewDevice === option"
            @click="previewDevice = option"
          />
        </div>
      </div>
      <div
        class="max-h-[62vh] overflow-y-auto rounded-xl border border-n-weak bg-n-alpha-1 p-3"
      >
        <Spinner v-if="isPreviewLoading" />
        <div
          v-else
          class="mx-auto w-full"
          :class="
            previewDevice === 'mobile' ? 'max-w-[22rem]' : 'max-w-[37.5rem]'
          "
        >
          <iframe
            v-if="previewHtml"
            :srcdoc="previewHtml"
            :title="displayName(previewTemplate)"
            sandbox=""
            referrerpolicy="no-referrer"
            class="h-[70rem] w-full border-0 bg-white"
          />
          <p v-else class="p-6 text-sm text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.NO_PREVIEW') }}
          </p>
        </div>
      </div>
    </Dialog>
  </section>
</template>
