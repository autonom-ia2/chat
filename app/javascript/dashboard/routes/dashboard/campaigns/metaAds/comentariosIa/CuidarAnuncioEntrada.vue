<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';

// Anúncios da Meta (#2212, B2): a entrada "A IA cuida dos comentários" no anúncio por dentro, logo acima dos
// comentários. Leva à tela de cuidar do anúncio (campaigns_meta_ads_cuidar) e mostra se a IA já cuida dele ou está
// pausada, pelo estado guardado (GET meta_ads_connection/cuidados, só banco: não lê os comentários na Meta). Falha ao
// ler o estado: a entrada fica, sem o selo.
const props = defineProps({
  adId: { type: String, required: true },
  canManage: { type: Boolean, default: false },
});

const KEY = 'META_ADS_COMMENTS_AI.ENTRY';
const route = useRoute();
const care = ref('off');

const lerEstado = async () => {
  const asked = props.adId;
  care.value = 'off';
  try {
    const { data } = await ComentariosIaAPI.getCuidadosDosAnuncios();
    const estado = (data.cuidados || []).find(item => item.ad_id === asked);
    if (asked === props.adId) care.value = estado?.care || 'off';
  } catch {
    // Sem o estado, a entrada continua levando à tela, que lê tudo de novo.
  }
};
watch(() => props.adId, lerEstado, { immediate: true });

const on = computed(() => care.value !== 'off');
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
    :data-care="care"
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
      <p v-if="!on" class="m-0 text-sm leading-6 text-n-slate-11">
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
    <router-link
      :to="destino"
      data-ia-ad-entry-open
      class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-n-brand px-4 text-sm font-medium text-white no-underline hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2 max-sm:w-full"
    >
      <span class="i-lucide-sparkles size-4" aria-hidden="true" />
      {{ $t(`${KEY}.${acao}`) }}
    </router-link>
  </section>
</template>
