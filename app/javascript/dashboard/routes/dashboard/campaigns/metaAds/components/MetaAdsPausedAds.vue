<script setup>
import { onMounted, ref, watch } from 'vue';
import { lerPausadosEsperando } from '../criacaoNaMeta';
import MetaAdsPausedAd from './MetaAdsPausedAd.vue';

// O painel sabe quantos há: com pausados à vista, o "Criar anúncio" sai do azul cheio (um primário por tela).
const emit = defineEmits(['count']);
// Anúncios da Meta (#2198): anúncios criados por aqui que seguem pausados, no topo do Resultado. O painel lista
// pelo que já gastou, e um anúncio novo e pausado não gastou nada: sem este bloco, quem volta ao painel sem ativar
// não acha mais o anúncio. Cada um com o "Ativar anúncio", que mostra quanto vai gastar antes de começar
// (MetaAdsPausedAd lê o orçamento de agora). Ativado, a lista é lida de novo: quem saiu da pausa sai dela.
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PAUSED_LIST';

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
      <MetaAdsPausedAd
        v-for="ad in ads"
        :key="ad.ad_id"
        :ad="ad"
        @changed="activated"
      />
    </ul>
  </section>
</template>
