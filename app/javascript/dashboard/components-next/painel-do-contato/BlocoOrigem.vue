<script setup>
// #2138 — "De onde veio": a origem do primeiro toque, escrita por inteiro (o topo
// só mostra a marca curta). Sem origem, some; um 403 também esconde, sem aviso.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignJourneyAPI from 'dashboard/api/campaignJourney';
import { buildCrmOrigin } from 'dashboard/routes/dashboard/crm/composables/useCrmOrigin';
import BlocoDoPainel from './BlocoDoPainel.vue';
import EsqueletoOuErro from './EsqueletoOuErro.vue';
import { ESTADO, useParteDoPainel } from './useParteDoPainel';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  conversationAttributes: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
// As marcas do contato; sem elas (vazio), valem as da conversa aberta.
const { estado, dados, carregar, esconder } = useParteDoPainel(
  async () => {
    const { data } = await CampaignJourneyAPI.getContactOrigins(
      props.contactId
    );
    return data.payload?.marks || [];
  },
  () => true
);
watch(
  () => props.contactId,
  id => (id ? carregar() : esconder()),
  { immediate: true }
);

const daConversa = computed(() => {
  const { campaign_touches: toques, campaign } = props.conversationAttributes;
  if (Array.isArray(toques)) return toques;
  return campaign ? [campaign] : [];
});

const origem = computed(
  () =>
    (dados.value?.length ? dados.value : daConversa.value)
      .map(buildCrmOrigin)
      .filter(Boolean)[0]
);

const CANAL = {
  google_ads: 'Google',
  tiktok_ads: 'TikTok',
};
const ANUNCIOS = ['meta_ctwa', 'meta_paid', 'google_ads', 'tiktok_ads'];

const frase = computed(() => {
  const o = origem.value;
  if (!o) return '';
  const nome = o.ad || o.campaign || o.headline;
  if (ANUNCIOS.includes(o.source)) {
    const canal = CANAL[o.source];
    if (canal)
      return nome
        ? t('PAINEL_DO_CONTATO.ORIGEM.ANUNCIO_NO', { canal, nome })
        : t('PAINEL_DO_CONTATO.ORIGEM.ANUNCIO_NO_SEM_NOME', { canal });
    return nome
      ? t('PAINEL_DO_CONTATO.ORIGEM.ANUNCIO', { nome })
      : t('PAINEL_DO_CONTATO.ORIGEM.ANUNCIO_SEM_NOME');
  }
  if (o.source === 'tracked_link')
    return nome
      ? t('PAINEL_DO_CONTATO.ORIGEM.LINK', { nome })
      : t('PAINEL_DO_CONTATO.ORIGEM.LINK_SEM_NOME');
  if (o.source === 'meta_organic')
    return nome
      ? t('PAINEL_DO_CONTATO.ORIGEM.PUBLICACAO', { nome })
      : t('PAINEL_DO_CONTATO.ORIGEM.PUBLICACAO_SEM_NOME');
  return nome
    ? t('PAINEL_DO_CONTATO.ORIGEM.CAMPANHA', { nome })
    : t('PAINEL_DO_CONTATO.ORIGEM.CAMPANHA_SEM_NOME');
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <BlocoDoPainel
    v-if="estado === ESTADO.CARREGANDO"
    data-test-id="bloco-origem-carregando"
  >
    <EsqueletoOuErro :estado="estado" :linhas="1" />
  </BlocoDoPainel>
  <BlocoDoPainel
    v-else-if="estado === ESTADO.ERRO || (estado !== ESTADO.ESCONDIDO && frase)"
    :titulo="t('PAINEL_DO_CONTATO.ORIGEM.TITULO')"
    data-test-id="bloco-origem"
  >
    <EsqueletoOuErro
      v-if="estado === ESTADO.ERRO"
      :estado="estado"
      @tentar="carregar"
    />
    <p v-else class="m-0 text-sm text-n-slate-12">{{ frase }}</p>
  </BlocoDoPainel>
</template>
