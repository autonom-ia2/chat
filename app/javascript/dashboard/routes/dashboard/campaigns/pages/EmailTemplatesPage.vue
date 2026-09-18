<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { buildTemplateCampaignPayload } from './emailTemplateBody';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const canManage = useCanManage('campaign_manage');

const campaigns = useMapGetter('emailCampaigns/getCampaigns');

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
// Monotonic token so a slow preview fetch can't overwrite a newer one.
let previewSeq = 0;

const categories = computed(() => {
  const unique = new Set(
    templates.value.map(item => item.category).filter(Boolean)
  );
  return ['all', ...Array.from(unique).sort()];
});

const filteredTemplates = computed(() => {
  if (activeCategory.value === 'all') return templates.value;
  return templates.value.filter(item => item.category === activeCategory.value);
});

const categoryLabel = category => {
  if (category === 'all') {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.ALL_CATEGORIES');
  }
  return t(`CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.CATEGORIES.${category}`, category);
};

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
    if (isUnmounted) return;
    thumbHtml.value = { ...thumbHtml.value, [id]: data.body_html || '' };
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
  previewHtml.value = '';
  // The gallery index payload is lightweight (no body); fetch the full template so we can
  // render its compiled HTML. body_html is compiled at seed time; fall back gracefully if absent.
  isPreviewLoading.value = true;
  // Race guard: capture a token; only the latest open may apply its response.
  previewSeq += 1;
  const requestSeq = previewSeq;
  try {
    const { data } = await EmailCampaignTemplatesAPI.show(template.id);
    if (isUnmounted || requestSeq !== previewSeq) return;
    previewHtml.value = data.body_html || '';
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
      router.push({
        name: 'campaigns_email_index',
        params: { accountId: route.params.accountId },
      });
    }
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.APPLY_ERROR'));
  } finally {
    isApplying.value = false;
    closePreview();
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

  if (campaignId.value && !campaigns.value.length) {
    await store.dispatch('emailCampaigns/get');
  }
  await fetchTemplates();
});

onBeforeUnmount(() => {
  isUnmounted = true;
  if (thumbObserver) {
    thumbObserver.disconnect();
    thumbObserver = null;
  }
  cardEls.clear();
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full min-h-0 bg-n-surface-1">
    <div
      class="flex items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-2">
        <Button
          icon="i-lucide-arrow-left"
          color="slate"
          variant="ghost"
          size="sm"
          @click="goBack()"
        />
        <p class="mb-0 font-medium truncate text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.TITLE') }}
        </p>
      </div>
    </div>

    <div
      v-if="!isLoading && categories.length > 1"
      class="flex flex-wrap items-center gap-2 px-4 py-3 border-b border-n-weak"
    >
      <Button
        v-for="category in categories"
        :key="category"
        :label="categoryLabel(category)"
        size="sm"
        :color="activeCategory === category ? 'blue' : 'slate'"
        :variant="activeCategory === category ? 'solid' : 'outline'"
        @click="activeCategory = category"
      />
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <div
        v-if="isLoading"
        class="flex items-center justify-center h-full text-n-slate-11"
      >
        <Spinner />
      </div>

      <div
        v-else-if="!filteredTemplates.length"
        class="flex flex-col items-center justify-center h-full gap-2 text-n-slate-11"
      >
        <span class="i-lucide-layout-template text-2xl" />
        <p class="mb-0 text-sm">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.EMPTY') }}
        </p>
      </div>

      <div
        v-else
        class="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          v-for="template in filteredTemplates"
          :key="template.id"
          :ref="el => registerCard(template.id, el)"
          :data-template-id="template.id"
          class="flex flex-col overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
        >
          <button
            type="button"
            class="relative flex items-center justify-center h-40 overflow-hidden border-b bg-n-alpha-1 border-n-weak"
            @click="openPreview(template)"
          >
            <img
              v-if="template.thumbnail_url"
              :src="template.thumbnail_url"
              :alt="template.name"
              class="object-cover w-full h-full"
            />
            <div
              v-else-if="thumbHtml[template.id]"
              class="absolute inset-0 overflow-hidden bg-white pointer-events-none"
            >
              <iframe
                :srcdoc="thumbHtml[template.id]"
                :title="template.name"
                sandbox=""
                scrolling="no"
                loading="lazy"
                aria-hidden="true"
                class="w-[600px] h-[320px] origin-top-left scale-50 border-0 pointer-events-none"
              />
            </div>
            <Spinner v-else-if="thumbHtml[template.id] === undefined" />
            <span v-else class="i-lucide-image text-3xl text-n-slate-9" />
          </button>
          <div class="flex flex-col flex-1 gap-1 p-3">
            <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
              {{ template.name }}
            </p>
            <p v-if="template.category" class="mb-0 text-xs text-n-slate-11">
              {{ categoryLabel(template.category) }}
            </p>
            <div class="flex items-center gap-2 mt-2">
              <Button
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.PREVIEW')"
                color="slate"
                variant="outline"
                size="sm"
                class="flex-1"
                @click="openPreview(template)"
              />
              <Button
                v-if="canManage"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.USE')"
                color="blue"
                size="sm"
                class="flex-1"
                :is-loading="isApplying"
                @click="useTemplate(template)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="previewTemplate"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="closePreview"
    >
      <div
        class="flex max-h-[85vh] w-[min(48rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-xl"
      >
        <div
          class="flex items-start justify-between gap-3 p-6 pb-4 border-b border-n-weak"
        >
          <div class="min-w-0">
            <h3 class="mb-1 text-base font-medium leading-6 text-n-slate-12">
              {{ previewTemplate.name }}
            </h3>
            <p
              v-if="previewTemplate.category"
              class="mb-0 text-sm leading-5 text-n-slate-11"
            >
              {{ categoryLabel(previewTemplate.category) }}
            </p>
          </div>
          <Button
            icon="i-lucide-x"
            color="slate"
            variant="ghost"
            size="sm"
            @click="closePreview"
          />
        </div>

        <div class="flex flex-1 min-h-0 p-6 overflow-y-auto">
          <div
            v-if="isPreviewLoading"
            class="flex items-center justify-center flex-1 text-n-slate-11"
          >
            <Spinner />
          </div>
          <iframe
            v-else-if="previewHtml"
            :srcdoc="previewHtml"
            :title="previewTemplate.name"
            sandbox=""
            class="w-full min-h-[60vh] flex-1 rounded-lg border border-n-weak bg-white"
          />
          <img
            v-else-if="previewTemplate.thumbnail_url"
            :src="previewTemplate.thumbnail_url"
            :alt="previewTemplate.name"
            class="self-center max-w-full mx-auto rounded-lg"
          />
          <div
            v-else
            class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-11"
          >
            <span class="i-lucide-image text-3xl text-n-slate-9" />
            <p class="mb-0 text-sm">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.NO_PREVIEW') }}
            </p>
          </div>
        </div>

        <div
          class="flex items-center justify-end w-full gap-3 p-6 pt-4 border-t border-n-weak bg-n-alpha-2"
        >
          <Button
            variant="faded"
            color="slate"
            type="button"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.CANCEL')"
            @click="closePreview"
          />
          <Button
            v-if="canManage"
            type="button"
            color="blue"
            icon="i-lucide-check"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.GALLERY.USE')"
            :is-loading="isApplying"
            @click="useTemplate(previewTemplate)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
