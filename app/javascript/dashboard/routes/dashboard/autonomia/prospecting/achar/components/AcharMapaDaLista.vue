<script setup>
import { computed } from 'vue';
import ProspectingGoogleMap from '../../components/ProspectingGoogleMap.vue';

// #2692 — o mapa das empresas achadas, ao lado da lista (1440) ou em tela cheia
// (390). É o mapa de verdade da tela de hoje (ProspectingGoogleMap.vue), com a
// mesma chave de navegador da plataforma (GOOGLE_MAPS_BROWSER_API_KEY, que o
// layout põe em window.chatwootConfig, como em MapaDoWhatsapp.vue). Sem a
// chave, o componente mostra o aviso de sempre ("O mapa ainda não está
// disponível na plataforma.") e nenhum pino.
// O pino segue a cor da chance; "Chame primeiro" é maior; quem não vai (ou
// fica de fora) fica apagado. Clicar no pino destaca a empresa na lista.
const props = defineProps({
  empresas: { type: Array, required: true },
  primeiroId: { type: [Number, String], default: null },
  naoVai: { type: Set, required: true },
  destacada: { type: [Number, String], default: null },
  heightClass: { type: String, default: 'h-96' },
});
const emit = defineEmits(['selecionar']);

// Cores fixas porque o Google desenha o pino fora do CSS da página. São as
// mesmas famílias do selo de chance (acharChance.js): teal, blue, amber, slate.
const CORES = {
  primeiro: '#12a594',
  boa: '#0d74ce',
  media: '#ffb224',
  pouca: '#8b8d98',
};

const chave = window.chatwootConfig?.googleMapsBrowserApiKey || '';

const leads = computed(() =>
  props.empresas
    .filter(empresa => empresa.latitude != null && empresa.longitude != null)
    .map(empresa => {
      const primeiro = empresa.id === props.primeiroId;
      return {
        id: empresa.id,
        name: empresa.nome,
        latitude: empresa.latitude,
        longitude: empresa.longitude,
        color: primeiro ? CORES.primeiro : CORES[empresa.chance] || CORES.pouca,
        dimmed: Boolean(empresa.fora) || props.naoVai.has(empresa.id),
        featured: primeiro,
      };
    })
);

const estiloDoPino = lead => ({
  color: lead.color,
  dimmed: lead.dimmed,
  featured: lead.featured,
});
</script>

<template>
  <ProspectingGoogleMap
    :api-key="chave"
    :leads="leads"
    :pin-style="estiloDoPino"
    :selected-id="destacada"
    :cluster="false"
    :height-class="heightClass"
    data-mapa-da-lista
    @select-lead="emit('selecionar', $event.id)"
  />
</template>
