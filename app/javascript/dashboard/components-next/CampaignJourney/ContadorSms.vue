<script setup>
// Quantos caracteres e em quantas partes vai um texto de SMS (smsSegments.js): cada parte é cobrada. Usado na versão 2
// da mensagem (#3099) e na segunda mensagem do "Mandar de novo" (#3101).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatNumber } from './localeTag';
import { smsStats } from './smsSegments';

const props = defineProps({
  texto: { type: String, default: '' },
});

const SMS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.SMS';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const contagem = computed(() => smsStats(props.texto));
</script>

<template>
  <p class="m-0 text-xs text-n-slate-11" aria-live="polite">
    {{
      t(
        `${SMS}.COUNTER`,
        {
          characters: n(contagem.characters),
          segments: n(contagem.segments),
        },
        contagem.segments
      )
    }}
  </p>
</template>
