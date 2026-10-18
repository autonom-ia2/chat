<script setup>
// #1702: a miniatura do mapa no balão de localização, como no WhatsApp: imagem do
// Google Maps (Maps Static API) com a chave de navegador da plataforma
// (GOOGLE_MAPS_BROWSER_API_KEY, a mesma da Prospecção). Sem chave, sem pele ou com a
// imagem recusada, nada aparece e fica o mapa desenhado de sempre por baixo.
import { computed, ref } from 'vue';
import { usePele } from '../pele';

const props = defineProps({
  // "lat,long" já validado (mapLink.js pointOf).
  ponto: { type: String, required: true },
});

const pele = usePele();
const falhou = ref(false);
const chave = window.chatwootConfig?.googleMapsBrowserApiKey || '';

// 300 x 140 é o tamanho do mapa no balão; scale=2 para telas de alta densidade.
const endereco = computed(() => {
  const params = new URLSearchParams({
    center: props.ponto,
    zoom: '16',
    size: '300x140',
    scale: '2',
    language: 'pt-BR',
    key: chave,
  });
  return `https://maps.googleapis.com/maps/api/staticmap?${params}`;
});
</script>

<template>
  <!-- Invólucro sem caixa: a pele esconde o resto do ícone, não ele. -->
  <span class="contents" data-mapa-do-whatsapp>
    <img
      v-if="pele && chave && ponto && !falhou"
      :src="endereco"
      alt=""
      loading="lazy"
      class="absolute inset-0 size-full object-cover"
      @error="falhou = true"
    />
  </span>
</template>
