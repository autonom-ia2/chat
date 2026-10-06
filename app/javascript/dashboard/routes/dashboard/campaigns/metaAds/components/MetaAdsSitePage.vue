<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import { clockTime, relativeTime } from '../metaAdsHelpers';

// Anúncios da Meta (#1047), passo 3: uma página do site ligada em Links e QR codes (#1011).
// "Testar agora" (CA-1.6) abre a página e espera o primeiro aviso de clique chegar; a lista de
// campanhas (CA-1.7) confirma, campanha por campanha, que o texto dos anúncios foi colado.
const props = defineProps({
  page: { type: Object, required: true },
});

const POLL_MS = 5000;
const POLL_TRIES = 36;
const VISIBLE_CAMPAIGNS = 3;

const { t, locale } = useI18n();

const current = ref(props.page);
// idle | waiting | ok | timeout
const testState = ref('idle');
const confirmedAt = ref(null);
let timer = null;

const siteUrl = computed(() => current.value.allowed_origins?.[0] || '');
const named = computed(() =>
  (current.value.campaigns || []).filter(row => row.name)
);
const unnamedClicks = computed(() =>
  (current.value.campaigns || [])
    .filter(row => !row.name)
    .reduce((total, row) => total + row.clicks, 0)
);
const lastClick = computed(() => {
  const time = relativeTime(current.value.last_signal_at, locale.value);
  return time
    ? t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SITE_LAST', { time })
    : t('CRM_KANBAN.META_ADS_HUB.DESTINATIONS.SITE_NONE_YET');
});

const stop = () => {
  clearInterval(timer);
  timer = null;
};

const refresh = async () => {
  const { data } = await CtwaTrackedLinksAPI.get();
  return (data.payload || []).find(link => link.id === current.value.id);
};

const startTest = () => {
  // Compara com o aviso anterior, não com o relógio do navegador (pode estar adiantado).
  const before = current.value.last_signal_at;
  let tries = 0;
  testState.value = 'waiting';
  window.open(siteUrl.value, '_blank', 'noopener');
  stop();
  timer = setInterval(async () => {
    tries += 1;
    try {
      const fresh = await refresh();
      if (fresh) current.value = fresh;
    } catch {
      // Uma leitura falhou; a próxima tentativa tenta de novo.
    }
    const signal = current.value.last_signal_at;
    if (signal && signal !== before) {
      confirmedAt.value = clockTime(signal, locale.value);
      testState.value = 'ok';
      stop();
    } else if (tries >= POLL_TRIES) {
      testState.value = 'timeout';
      stop();
    }
  }, POLL_MS);
};

onBeforeUnmount(stop);
</script>

<template>
  <li
    :data-site-page="current.id"
    class="flex flex-col gap-3 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <span class="flex flex-col min-w-0 gap-0.5">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ current.name }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 text-xs"
          :class="current.last_signal_at ? 'text-n-teal-11' : 'text-n-slate-11'"
        >
          <span
            class="rounded-full size-2"
            :class="current.last_signal_at ? 'bg-n-teal-9' : 'bg-n-slate-7'"
            aria-hidden="true"
          />
          {{ lastClick }}
        </span>
      </span>
      <Button
        v-if="siteUrl"
        data-site-test
        class="!min-h-11 !rounded-xl"
        variant="faded"
        color="blue"
        size="sm"
        icon="i-lucide-mouse-pointer-click"
        :is-loading="testState === 'waiting'"
        :disabled="testState === 'waiting'"
        :label="$t('CRM_KANBAN.META_ADS_HUB.SITE.TEST')"
        @click="startTest"
      />
    </div>

    <p
      v-if="testState === 'waiting'"
      data-site-test-waiting
      role="status"
      class="px-3 py-2 m-0 text-sm rounded-lg bg-n-blue-2 text-n-blue-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.SITE.TEST_WAITING') }}
    </p>
    <p
      v-else-if="testState === 'ok'"
      data-site-test-ok
      role="status"
      class="px-3 py-2 m-0 text-sm font-semibold rounded-lg bg-n-teal-2 text-n-teal-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.SITE.TEST_OK', { time: confirmedAt }) }}
    </p>
    <p
      v-else-if="testState === 'timeout'"
      data-site-test-timeout
      role="status"
      class="px-3 py-2 m-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.SITE.TEST_TIMEOUT') }}
    </p>

    <div v-if="named.length || unnamedClicks" class="flex flex-col gap-1.5">
      <span class="text-xs font-semibold text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.SITE.CAMPAIGNS_TITLE') }}
      </span>
      <ul class="flex flex-col gap-1 p-0 m-0 list-none">
        <li
          v-for="row in named.slice(0, VISIBLE_CAMPAIGNS)"
          :key="row.campaign_key"
          data-site-campaign
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <span
            class="flex-none i-lucide-circle-check size-4 text-n-teal-11"
            aria-hidden="true"
          />
          <span class="truncate">{{ row.name }}</span>
        </li>
        <li
          v-if="named.length > VISIBLE_CAMPAIGNS"
          class="text-xs text-n-slate-11 ps-6"
        >
          {{
            $t('CRM_KANBAN.META_ADS_HUB.SITE.CAMPAIGNS_MORE', {
              count: named.length - VISIBLE_CAMPAIGNS,
            })
          }}
        </li>
        <li
          v-if="unnamedClicks"
          data-site-unnamed
          class="flex items-center gap-2 text-sm text-n-amber-11"
        >
          <span
            class="flex-none i-lucide-circle-alert size-4"
            aria-hidden="true"
          />
          {{
            $t(
              'CRM_KANBAN.META_ADS_HUB.SITE.UNNAMED',
              { count: unnamedClicks },
              unnamedClicks
            )
          }}
        </li>
      </ul>
    </div>
  </li>
</template>
