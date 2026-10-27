<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { longDate, money } from '../dinheiroDoAnuncio';
import { lerPausadosEsperando } from '../criacaoNaMeta';
import MetaAdsAdStatus from './MetaAdsAdStatus.vue';

// O painel sabe quantos há: com pausados à vista, o "Criar anúncio" sai do azul cheio (um primário por tela).
const emit = defineEmits(['count']);
// Anúncios da Meta (#2198): anúncios criados por aqui que seguem pausados, no topo do Resultado. O painel lista
// pelo que já gastou, e um anúncio novo e pausado não gastou nada: sem este bloco, quem volta ao painel sem ativar
// não acha mais o anúncio. Cada um com o "Ativar anúncio", que mostra quanto vai gastar antes de começar. Ativado, a
// lista é lida de novo: quem saiu da pausa sai dela.
const { locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PAUSED_LIST';
const PAUSED = {
  status: 'PAUSED',
  effective_status: 'PAUSED',
  can_change: true,
};

const ads = ref([]);
const failed = ref(false);

const load = async () => {
  failed.value = false;
  try {
    ads.value = await lerPausadosEsperando();
  } catch {
    ads.value = [];
    failed.value = true;
  }
};

watch(
  () => ads.value.length,
  count => emit('count', count)
);

const activated = status => {
  if (status === 'ACTIVE') load();
};

const perDay = ad => money(ad.budget.amount, ad.budget.currency, locale.value);

onMounted(load);
</script>

<template>
  <!-- v-show: sem pausados, o bloco não ocupa lugar nem cria espaço no painel. -->
  <section
    v-show="ads.length || failed"
    data-panel-paused
    class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-amber-6"
  >
    <div class="flex items-start gap-3">
      <span
        :class="failed ? 'i-lucide-cloud-off' : 'i-lucide-circle-pause'"
        class="mt-0.5 size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <div v-if="failed" role="alert" class="flex flex-col items-start gap-1">
        <p class="m-0 text-sm text-n-slate-12">{{ $t(`${KEY}.FAILED`) }}</p>
        <button
          type="button"
          data-panel-paused-retry
          class="-ml-3 inline-flex min-h-11 items-center gap-2 rounded-lg border-0 bg-transparent px-3 text-sm font-520 text-n-brand underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="load"
        >
          <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
          {{ $t(`${KEY}.RETRY`) }}
        </button>
      </div>
      <div v-else class="flex flex-col gap-0.5">
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t(`${KEY}.TITLE`, { count: ads.length }) }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">{{ $t(`${KEY}.HINT`) }}</p>
      </div>
    </div>
    <ul v-if="ads.length" class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="ad in ads"
        :key="ad.ad_id"
        :data-panel-paused-ad="ad.ad_id"
        class="flex flex-col gap-3 rounded-xl bg-n-alpha-1 p-4 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex min-w-0 flex-col gap-0.5">
          <span class="break-words text-sm font-semibold text-n-slate-12">
            {{ ad.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              $t(`${KEY}.LINE`, {
                date: longDate(ad.created_at, locale),
                value: perDay(ad),
              })
            }}
          </span>
        </div>
        <MetaAdsAdStatus
          :ad-id="ad.ad_id"
          :ad-name="ad.name"
          :gestao="PAUSED"
          :budget="ad.budget"
          can-manage
          tone="light"
          @changed="activated"
        />
      </li>
    </ul>
  </section>
</template>
