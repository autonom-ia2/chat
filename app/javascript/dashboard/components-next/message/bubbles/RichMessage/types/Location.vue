<script setup>
// Localização enviada: `{ type: 'location', latitude, longitude, name?, address? }`, sem corpo.
// Nome e endereço por extenso, sem carregar mapa de fora; o atendente pode abrir o ponto no mapa em outra aba.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import SharedCard from '../SharedCard.vue';

const { contentAttributes, sender } = useMessageContext();
const { t } = useI18n();

// O mesmo endereço de mapa está na versão em texto do envio
// (app/services/rich_messages/types/location.rb, MAP_LINK): mudou um, mude o outro.
const MAP_LINK = 'https://maps.google.com/?q=';

// Tudo vem de quem chamou a API: só texto entra na tela, e só número finito na faixa vira coordenada.
const textOf = value => (typeof value === 'string' ? value : '');
const coordinateOf = (value, limit) =>
  Number.isFinite(value) && Math.abs(value) <= limit ? value : null;

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});

const mapHref = computed(() => {
  const latitude = coordinateOf(richMessage.value.latitude, 90);
  const longitude = coordinateOf(richMessage.value.longitude, 180);
  if (latitude === null || longitude === null) return '';

  return `${MAP_LINK}${latitude},${longitude}`;
});

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
  />
</template>
