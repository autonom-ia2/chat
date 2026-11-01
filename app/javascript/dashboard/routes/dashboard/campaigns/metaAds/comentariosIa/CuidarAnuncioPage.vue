<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { lerGestao } from '../gestaoDoAnuncio';
import CuidarComentarios from './CuidarComentarios.vue';

// Anúncios da Meta (#2212, B2): "Cuidar dos comentários" de um anúncio. A tela é a mesma do post do Seus posts (B1,
// CuidarComentarios); esta página só a coloca no endereço do anúncio, lê o nome e o post dele (a gestão, #2161) para
// o cabeçalho e volta para o anúncio (?anuncio= no painel). O cuidado em si vem de GET
// meta_ads_connection/ads/:ad_id/cuidado, que diz as redes e a caixa. Mudar pede meta_ads_manage.
const route = useRoute();
const router = useRouter();

const adId = computed(() => String(route.params.adId));
const target = computed(() => ({ kind: 'ad', id: adId.value }));
const canManage = usePermissionGranted('meta_ads_manage');

// Sem a gestão (falhou a leitura), a tela de cuidar segue sem o cabeçalho do post.
const gestao = ref(null);
const lerAnuncio = async () => {
  const asked = adId.value;
  gestao.value = null;
  const data = await lerGestao(asked);
  if (asked === adId.value) gestao.value = data;
};
watch(adId, lerAnuncio, { immediate: true });

const cabecalho = computed(() => {
  const text = gestao.value?.post?.message || gestao.value?.name;
  return text ? { image_url: null, text } : null;
});

const caixa = inboxId =>
  frontendURL(`accounts/${route.params.accountId}/inbox/${inboxId}`);

const voltar = () =>
  router.push({
    name: 'campaigns_meta_ads_index',
    params: { accountId: route.params.accountId },
    query: { aba: 'resultado', anuncio: adId.value },
  });
</script>

<template>
  <section
    data-meta-ads-cuidar-tela
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div
      class="mx-auto flex w-full max-w-3xl flex-col gap-5 p-4 pb-24 sm:p-5 lg:p-8"
    >
      <CuidarComentarios
        :target="target"
        :post="cabecalho"
        origin="anuncio"
        :can-manage="canManage"
        :inbox-path-of="caixa"
        @back="voltar"
      />
    </div>
  </section>
</template>
