<script setup>
import { computed } from 'vue';
import { SINAIS, SINAIS_DE_ALERTA } from '../constants';

// Modelo pronto com nota ruim do WhatsApp (#1338): a campanha avisa ao escolher
// o modelo e na revisão, mas deixa enviar (decisão do Rodrigo).
const props = defineProps({
  modelo: { type: Object, default: null },
});

const sinal = computed(() =>
  props.modelo?.situacao === 'pronto' &&
  SINAIS_DE_ALERTA.includes(props.modelo.sinal)
    ? props.modelo.sinal
    : ''
);
</script>

<template>
  <!-- Sem nada para mostrar, o embrulho não ocupa lugar (display: contents). -->
  <div class="contents">
    <p
      v-if="sinal"
      :data-ponte-sinal="sinal"
      role="status"
      class="flex gap-2 p-3 mb-0 text-sm rounded-xl ring-1 ring-inset text-n-slate-12"
      :class="SINAIS[sinal].caixa"
    >
      <span
        class="size-4 mt-0.5 shrink-0"
        :class="[SINAIS[sinal].icone, SINAIS[sinal].cor]"
        aria-hidden="true"
      />
      {{ $t(`MODELOS_WHATSAPP.PONTE.SINAL.${sinal}`, { nome: modelo.nome }) }}
    </p>
  </div>
</template>
