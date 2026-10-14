<script setup>
// Localização que o cliente mandou (chat#1473, P5), lida de `content_attributes.shared_location`
// (`{ latitude, longitude, name?, address? }`, gravado por app/services/rich_messages/received_location.rb).
// O anexo de antes junta nome e endereço num título só e fica sem texto quando não há nome; aqui cada um tem
// a sua linha. Quem escolhe esta bolha é bubbles/Location.vue, só quando a mensagem traz `shared_location`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../provider.js';
import SharedCard from './SharedCard.vue';
import { mapHrefOf } from './mapLink.js';

const { contentAttributes, sender } = useMessageContext();
const { t } = useI18n();

// Vem do celular do cliente: só texto entra na tela (as coordenadas, o mapLink valida).
const textOf = value => (typeof value === 'string' ? value : '');

const location = computed(() => contentAttributes.value?.sharedLocation ?? {});

const mapHref = computed(() =>
  mapHrefOf(location.value.latitude, location.value.longitude)
);

const heading = computed(() => {
  const name = sender?.value?.name;
  return name ? t('RICH_MESSAGE.LOCATION.SHARED', { sender: name }) : '';
});
</script>

<template>
  <SharedCard
    bubble-name="received-location"
    icon="i-ph-navigation-arrow-fill"
    icon-bg-color="bg-n-teal-9"
    :heading="heading"
    :title="textOf(location.name)"
    :detail="textOf(location.address)"
    :action-label="t('RICH_MESSAGE.LOCATION.SEE_ON_MAP')"
    :action-href="mapHref"
  />
</template>
