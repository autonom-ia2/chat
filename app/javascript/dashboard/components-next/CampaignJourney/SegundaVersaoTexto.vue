<script setup>
// #3099 — a versão 2 de uma mensagem de texto livre (WhatsApp API e SMS): a caixa do texto, os mesmos campos do
// contato e do público para inserir, o atalho "Começar com o texto da versão 1" e, ao lado, as duas versões como o
// cliente vê. No SMS, o mesmo contador de caracteres e partes da versão 1 (smsSegments.js).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatNumber } from './localeTag';
import { PLUS } from './textMarks';
import {
  CONTACT_TOKENS,
  audienceColumnTokens,
  insertToken,
  renderTokens,
} from './audienceTokens';
import { smsStats } from './smsSegments';
import { CAMPAIGN_CHANNELS } from './campaignChannels';

const props = defineProps({
  canal: { type: String, required: true },
  texto: { type: String, default: '' },
  primeira: { type: String, default: '' },
  extraColumns: { type: Array, default: () => [] },
  sample: { type: Object, default: null },
  defaults: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update']);

const NS = 'DUAS_VERSOES.TEXTO';
const API = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.API';
const SMS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.SMS';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const caixa = ref(null);
const ehSms = computed(() => props.canal === CAMPAIGN_CHANNELS.SMS);

const botoes = computed(() => [
  ...CONTACT_TOKENS.map(item => ({
    token: item.token,
    label: t(`${API}.TOKENS.${item.labelKey}`),
  })),
  ...audienceColumnTokens(props.extraColumns).map(item => ({
    token: item.token,
    label: item.header,
  })),
]);
const rotuloDe = token =>
  botoes.value.find(item => item.token === token)?.label || token;
const comoChega = texto =>
  renderTokens(texto, {
    sample: props.sample,
    extraColumns: props.extraColumns,
    defaults: props.defaults,
    placeholder: token => `[${rotuloDe(token)}]`,
  });
const versoes = computed(() => [
  { numero: 1, texto: props.primeira },
  { numero: 2, texto: props.texto },
]);
const contagem = computed(() => smsStats(props.texto));
// No SMS, cada parte é cobrada: quando as duas versões usam quantidades diferentes, a pessoa precisa saber.
const partesDiferentes = computed(() => {
  if (!ehSms.value || !props.texto || !props.primeira) return null;
  const da1 = smsStats(props.primeira).segments;
  const da2 = contagem.value.segments;
  return da1 === da2 ? null : { a: n(da1), b: n(da2) };
});

const inserir = token => {
  const atual = props.texto || '';
  const ponto = caixa.value?.selectionStart ?? atual.length;
  emit('update', insertToken(atual, token, ponto));
};
</script>

<template>
  <div
    class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start"
    data-segunda-versao-texto
  >
    <div class="flex min-w-0 flex-col gap-2">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <label
          for="segunda-versao-texto"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.ROTULO`) }}
        </label>
        <Button
          v-if="!texto && primeira"
          :label="t(`${NS}.COMECAR_DA_1`)"
          icon="i-lucide-copy"
          variant="ghost"
          size="sm"
          class="!min-h-11"
          data-comecar-da-1
          @click="emit('update', primeira)"
        />
      </div>
      <textarea
        id="segunda-versao-texto"
        ref="caixa"
        :value="texto"
        rows="4"
        :placeholder="t(`${NS}.PLACEHOLDER`)"
        class="m-0 w-full rounded-xl lg:min-h-40 border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        data-texto-da-2
        @input="evento => emit('update', evento.target.value)"
      />
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-xs text-n-slate-11">{{ t(`${API}.INSERT`) }}</span>
          <button
            v-for="item in botoes"
            :key="item.token"
            type="button"
            class="min-h-11 rounded-xl border border-n-weak px-3 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-label="t(`${API}.INSERT_ARIA`, { field: item.label })"
            @click="inserir(item.token)"
          >
            {{ PLUS }} {{ item.label }}
          </button>
        </div>
        <p
          v-if="ehSms"
          class="m-0 text-xs text-n-slate-11"
          aria-live="polite"
          data-contador-da-2
        >
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
      </div>
      <p
        v-if="partesDiferentes"
        class="m-0 text-xs text-n-slate-11"
        data-partes-diferentes
      >
        {{ t(`${NS}.PARTES_DIFERENTES`, partesDiferentes) }}
      </p>
    </div>

    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
      data-como-chega
    >
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.COMO_FICA`) }}
      </h3>
      <div
        v-for="versao in versoes"
        :key="versao.numero"
        class="flex flex-col gap-1.5 rounded-2xl p-3"
        :class="ehSms ? 'bg-n-solid-1' : 'bg-n-teal-2'"
        :data-previa-versao="versao.numero"
      >
        <span class="text-xs font-semibold text-n-slate-11">
          {{ t('DUAS_VERSOES.MENSAGEM.VERSAO', { n: versao.numero }) }}
        </span>
        <p
          v-if="versao.texto"
          class="m-0 max-w-xs whitespace-pre-wrap rounded-2xl rounded-tl-sm px-3 py-2 text-sm text-n-slate-12"
          :class="ehSms ? 'bg-n-alpha-2' : 'bg-n-solid-1 shadow-sm'"
        >
          {{ comoChega(versao.texto) }}
        </p>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.AINDA_VAZIA`) }}
        </p>
      </div>
    </aside>
  </div>
</template>
