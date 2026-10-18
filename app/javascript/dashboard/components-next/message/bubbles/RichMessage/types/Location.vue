<script setup>
// Localização enviada: `{ type: 'location', latitude, longitude, name?, address? }`, sem corpo.
// Nome e endereço por extenso; o atendente pode abrir o ponto no mapa em outra aba. Com a pele do WhatsApp
// (#1702), a miniatura do Google Maps entra no lugar do ícone.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import SharedCard from '../SharedCard.vue';
import { mapHrefOf, pointOf } from '../mapLink.js';

const { contentAttributes, sender } = useMessageContext();
const { t } = useI18n();

// Tudo vem de quem chamou a API: só texto entra na tela (as coordenadas, o mapLink valida).
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});

const mapHref = computed(() =>
  mapHrefOf(richMessage.value.latitude, richMessage.value.longitude)
);

const point = computed(() =>
  pointOf(richMessage.value.latitude, richMessage.value.longitude)
);

const heading = computed(() => {
  const name = sender?.value?.name;
  return name ? t('RICH_MESSAGE.LOCATION.SHARED', { sender: name }) : '';
});
</script>

<template>
  <SharedCard
    bubble-name="rich-location"
    icon="i-ph-navigation-arrow-fill"
    icon-bg-color="bg-n-teal-9"
    :heading="heading"
    :title="textOf(richMessage.name)"
    :detail="textOf(richMessage.address)"
    :action-label="t('RICH_MESSAGE.LOCATION.SEE_ON_MAP')"
    :action-href="mapHref"
    :mapa="point"
  />
</template>
