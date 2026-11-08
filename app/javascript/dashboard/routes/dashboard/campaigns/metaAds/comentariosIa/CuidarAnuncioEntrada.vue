<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';

// Anúncios da Meta (#2212, B2): a entrada "A IA cuida dos comentários" no anúncio por dentro, logo acima dos
// comentários. Leva à tela de cuidar do anúncio (campaigns_meta_ads_cuidar) e mostra se a IA já cuida dele ou está
// pausada, pelo estado guardado (GET meta_ads_connection/cuidados, só banco: não lê os comentários na Meta). Até o
// estado chegar, a entrada fica neutra, sem botão (não chama para cuidar de um anúncio que já está cuidado). Falha ao
// ler o estado: um aviso curto com "Tentar de novo".
const props = defineProps({
  adId: { type: String, required: true },
  canManage: { type: Boolean, default: false },
});

const KEY = 'META_ADS_COMMENTS_AI.ENTRY';
const route = useRoute();
// null: lendo; 'error': não deu para ler; senão, 'off', 'on' ou 'paused'.
const care = ref(null);

const lerEstado = async () => {
  const asked = props.adId;
  care.value = null;
  try {
    const { data } = await ComentariosIaAPI.getCuidadosDosAnuncios();
    const estado = (data.cuidados || []).find(item => item.ad_id === asked);
    if (asked === props.adId) care.value = estado?.care || 'off';
  } catch {
    if (asked === props.adId) care.value = 'error';
  }
};
watch(() => props.adId, lerEstado, { immediate: true });

const known = computed(() => ['off', 'on', 'paused'].includes(care.value));
const on = computed(() => ['on', 'paused'].includes(care.value));
const destino = computed(() => ({
  name: 'campaigns_meta_ads_cuidar',
  params: { accountId: route.params.accountId, adId: props.adId },
}));
const acao = computed(() => {
  if (!on.value) return props.canManage ? 'START' : 'SEE';
  return props.canManage ? 'CHANGE' : 'SEE';
});
</script>

<template>
  <section
    data-ia-ad-entry
    :data-care="care || 'loading'"
    :aria-busy="care === null"
    class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:flex-row sm:items-center sm:p-6"
  >
    <span
      class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-violet-3 text-n-violet-11"
      aria-hidden="true"
    >
      <span class="i-lucide-sparkles size-5" />
    </span>
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${KEY}.TITLE`) }}
      </h4>
      <p
        v-if="care === 'error'"
        role="alert"
        data-ia-ad-entry-error
        class="m-0 text-sm leading-6 text-n-slate-11"
      >
        {{ $t(`${KEY}.ERROR`) }}
      </p>
      <p v-else-if="!on" class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t(`${KEY}.TEXT`) }}
      </p>
      <span
        v-else
        data-ia-ad-entry-badge
        class="inline-flex min-h-8 items-center gap-2 self-start rounded-full px-3 text-sm font-medium"
        :class="
          care === 'on'
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
      >
        <span
          class="size-2 rounded-full"
          :class="care === 'on' ? 'bg-n-teal-9' : 'bg-n-amber-9'"
          aria-hidden="true"
        />
        {{
          care === 'on'
            ? $t('META_ADS_COMMENTS_AI.BADGE_ON')
            : $t('META_ADS_COMMENTS_AI.BADGE_PAUSED')
        }}
      </span>
    </div>
    <button
      v-if="care === 'error'"
      type="button"
      data-ia-ad-entry-retry
      class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand max-sm:w-full"
      @click="lerEstado"
    >
      <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
      {{ $t('META_ADS_COMMENTS_AI.SCREEN.RETRY') }}
    </button>
    <router-link
      v-else-if="known"
      :to="destino"
      data-ia-ad-entry-open
      class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-n-brand px-4 text-sm font-medium text-white no-underline hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2 max-sm:w-full"
    >
      <span class="i-lucide-sparkles size-4" aria-hidden="true" />
      {{ $t(`${KEY}.${acao}`) }}
    </router-link>
  </section>
</template>
