<script setup>
// Etiqueta do dia no meio da conversa (#1702): "Hoje", "Ontem", o dia da semana ou a
// data, no fuso da conta, como no WhatsApp. Gruda no topo enquanto a conversa rola;
// quando a etiqueta do dia seguinte chega ao topo, esta some (as etiquetas presas não
// se empilham). Elas são irmãs na mesma lista, então o sticky sozinho não resolve.
import { computed, onBeforeUnmount, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFuso } from './pele';
import { useAgora } from './useAgora';
import { idiomaDoPainel, rotuloDoDia } from './dataDaConversa';
import { coberta, proximoSeparador } from './separadorDeDia';
import { CLASSES_DO_SEPARADOR_DE_DIA } from './visualWhatsapp';

const props = defineProps({
  quando: { type: Number, required: true },
});

const { t, locale } = useI18n();
const fuso = useFuso();
// Passando da meia-noite com a conversa aberta, "Hoje" vira "Ontem".
const agora = useAgora();

const rotulo = computed(() =>
  rotuloDoDia({
    quando: props.quando,
    agora: agora.value,
    fuso: fuso.value,
    t,
    idioma: idiomaDoPainel(locale.value),
  })
);

const item = useTemplateRef('item');
const escondida = ref(false);
let proximo = null;
let quadro = 0;
const conferir = () => {
  quadro = 0;
  if (!item.value) return;
  if (!proximo?.isConnected) proximo = proximoSeparador(item.value);
  escondida.value = coberta(item.value, proximo);
};
const aoRolar = () => {
  if (!quadro) quadro = requestAnimationFrame(conferir);
};
// A rolagem é da lista da conversa; na captura, qualquer rolagem chega aqui.
onMounted(() => {
  window.addEventListener('scroll', aoRolar, { capture: true, passive: true });
  aoRolar();
});
onBeforeUnmount(() => {
  window.removeEventListener('scroll', aoRolar, { capture: true });
  if (quadro) cancelAnimationFrame(quadro);
});
</script>

<template>
  <li
    ref="item"
    class="sticky top-2 z-10 flex justify-center list-none my-3 pointer-events-none"
    data-separador-de-dia
  >
    <span
      :class="[CLASSES_DO_SEPARADOR_DE_DIA, { 'opacity-0': escondida }]"
      :aria-hidden="escondida || undefined"
    >
      {{ rotulo }}
    </span>
  </li>
</template>
