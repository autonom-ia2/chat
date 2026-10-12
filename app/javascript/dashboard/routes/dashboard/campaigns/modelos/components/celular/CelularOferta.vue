<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Oferta por tempo limitado na prévia: o título, a contagem regressiva até o
// fim e o cupom, como o WhatsApp mostra em cima do texto.
const props = defineProps({
  oferta: { type: Object, required: true },
});

const { t } = useI18n();
const HORA_MS = 60 * 60 * 1000;
const DIA_MS = 24 * HORA_MS;

const faltam = computed(() => {
  const ms = new Date(props.oferta.terminaEm).getTime() - Date.now();
  if (!props.oferta.terminaEm || Number.isNaN(ms) || ms <= 0) {
    return t('MODELOS_WHATSAPP.CELULAR.OFERTA_ACABOU');
  }
  const dias = Math.floor(ms / DIA_MS);
  const horas = Math.floor((ms % DIA_MS) / HORA_MS);
  const partes = [
    dias ? t('MODELOS_WHATSAPP.CELULAR.DIAS', { n: dias }, dias) : '',
    horas ? t('MODELOS_WHATSAPP.CELULAR.HORAS', { n: horas }, horas) : '',
  ].filter(Boolean);
  return t('MODELOS_WHATSAPP.CELULAR.OFERTA_TERMINA', {
    tempo: partes.length
      ? partes.join(t('MODELOS_WHATSAPP.CELULAR.E'))
      : t('MODELOS_WHATSAPP.CELULAR.MENOS_DE_1_HORA'),
  });
});
</script>

<template>
  <div
    data-celular-oferta
    class="flex items-start gap-2.5 p-2.5 rounded-lg bg-n-slate-2"
  >
    <span
      class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-ruby-3 text-n-ruby-11"
    >
      <span class="i-lucide-timer size-5" aria-hidden="true" />
    </span>
    <span class="flex flex-col min-w-0">
      <span class="text-sm font-semibold break-words text-n-slate-12">
        {{ oferta.titulo || $t('MODELOS_WHATSAPP.CELULAR.VAZIO') }}
      </span>
      <span class="text-xs text-n-ruby-11">{{ faltam }}</span>
      <span v-if="oferta.cupom" class="text-xs text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.CELULAR.CUPOM', { cupom: oferta.cupom }) }}
      </span>
    </span>
  </div>
</template>
