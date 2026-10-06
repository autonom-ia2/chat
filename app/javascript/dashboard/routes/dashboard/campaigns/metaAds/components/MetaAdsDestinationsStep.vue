<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import { errorMessageKey } from '../metaAdsHelpers';
import MetaAdsSitePage from './MetaAdsSitePage.vue';
import MetaAdsDestinationArt from './MetaAdsDestinationArt.vue';

// Anúncios da Meta (#1047), passo 3: para onde os anúncios levam. WhatsApp direto já funciona
// sozinho; site usa as páginas ligadas em Links e QR codes (#1011) e o texto dos parâmetros de URL.
const props = defineProps({
  destinations: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();

const choice = ref({
  whatsapp: props.destinations.whatsapp ?? false,
  site: props.destinations.site ?? false,
});
const sitePages = ref([]);
const saving = ref(false);

const OPTIONS = [
  { key: 'whatsapp', icon: 'i-lucide-message-circle' },
  { key: 'site', icon: 'i-lucide-globe' },
];

const adText = computed(() => sitePages.value[0]?.ad_url_params || '');
const canSave = computed(() => choice.value.whatsapp || choice.value.site);

const loadPages = async () => {
  try {
    const { data } = await CtwaTrackedLinksAPI.get();
    sitePages.value = (data.payload || []).filter(
      link => link.usage === 'website'
    );
  } catch {
    sitePages.value = [];
  }
};

const copyAdText = async () => {
  try {
    await navigator.clipboard.writeText(adText.value);
    useAlert(t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.COPIED'));
  } catch {
    // O texto segue visível para copiar à mão.
  }
};

const save = async () => {
  if (!canSave.value) {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.PICK_ONE'));
    return;
  }
  saving.value = true;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.updateDestinations(
      choice.value
    );
    useAlert(t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SAVED'));
    emit('saved', data);
  } catch (error) {
    useAlert(t(errorMessageKey(error)));
  } finally {
    saving.value = false;
  }
};

onMounted(loadPages);
</script>

<template>
  <section data-meta-ads-destinations class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <h3 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
        {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.TITLE') }}
      </h3>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.HINT') }}
      </p>
    </header>

    <div class="grid gap-3 md:grid-cols-2">
      <button
        v-for="option in OPTIONS"
        :key="option.key"
        type="button"
        :data-destination="option.key"
        :aria-pressed="choice[option.key]"
        class="flex flex-col w-full min-w-0 gap-3 p-3 text-left border border-solid rounded-2xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          choice[option.key]
            ? 'border-n-blue-8 bg-n-blue-2'
            : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
        "
        @click="choice = { ...choice, [option.key]: !choice[option.key] }"
      >
        <MetaAdsDestinationArt :kind="option.key" />
        <span class="flex items-start w-full gap-3 px-1">
          <span
            class="grid flex-none rounded-xl size-9 place-items-center bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            <span :class="option.icon" class="size-5" />
          </span>
          <span class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="text-sm font-semibold text-n-slate-12">
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.DESTINATIONS.${option.key.toUpperCase()}`
                )
              }}
            </span>
            <span class="text-xs leading-5 text-n-slate-11">
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.DESTINATIONS.${option.key.toUpperCase()}_WHEN`
                )
              }}
            </span>
          </span>
          <span
            class="grid flex-none border-2 rounded-md size-6 place-items-center"
            :class="
              choice[option.key]
                ? 'bg-n-blue-9 border-n-blue-9 text-white'
                : 'border-n-slate-7'
            "
            aria-hidden="true"
          >
            <span v-if="choice[option.key]" class="i-lucide-check size-4" />
          </span>
        </span>
      </button>
    </div>

    <div
      v-if="choice.site"
      data-site-setup
      class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
    >
      <div class="flex flex-col gap-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SITE_LINKS') }}
        </span>
        <ul
          v-if="sitePages.length"
          class="flex flex-col gap-2 p-0 m-0 list-none"
        >
          <MetaAdsSitePage
            v-for="page in sitePages"
            :key="page.id"
            :page="page"
          />
        </ul>
        <div v-else class="flex flex-wrap items-center gap-3">
          <span class="text-sm text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SITE_EMPTY') }}
          </span>
          <router-link
            :to="{ name: 'campaigns_tracked_links_index' }"
            class="text-sm font-semibold underline rounded text-n-blue-11 underline-offset-2"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SITE_CREATE') }}
          </router-link>
        </div>
      </div>

      <!-- O texto é para a Meta, não para a pessoa: só o botão de copiar aparece; o caminho e o
           próprio texto ficam em "Onde colar na Meta?". -->
      <div
        v-if="adText"
        data-ad-text-block
        class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-1"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.AD_TEXT_TITLE') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.AD_TEXT_HINT') }}
        </span>
        <div>
          <Button
            class="!min-h-11 !rounded-xl"
            data-copy-ad-text
            icon="i-lucide-copy"
            :label="$t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.COPY_TEXT')"
            @click="copyAdText"
          />
        </div>
        <details class="text-xs text-n-slate-11">
          <summary class="cursor-pointer select-none">
            {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.WHERE') }}
          </summary>
          <p class="mt-2 mb-2">
            {{ $t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.WHERE_TEXT') }}
          </p>
          <code
            data-ad-text
            class="block p-3 font-mono break-all border rounded-lg select-all border-n-slate-5 bg-n-solid-1 text-n-slate-12"
          >
            {{ adText }}
          </code>
        </details>
      </div>
    </div>

    <div>
      <Button
        class="!min-h-11 !rounded-xl"
        data-save-destinations
        icon="i-lucide-arrow-right"
        trailing-icon
        :is-loading="saving"
        :disabled="saving"
        :label="$t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SAVE')"
        @click="save"
      />
    </div>
  </section>
</template>
