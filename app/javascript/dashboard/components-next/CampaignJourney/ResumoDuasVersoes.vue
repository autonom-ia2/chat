<script setup>
// #3099 — a linha "Duas versões da mensagem" do passo Revisar: as duas versões lado a lado (o começo do texto, o nome
// do modelo ou o assunto) e o plano nas mesmas frases do passo Mensagem. "Alterar" volta ao passo Mensagem, como as
// outras linhas da revisão. Entra na revisão por um slot que a F5 (#3101) e esta fase combinam no PR de ligação: não
// mexe no "Quando começa".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFrasesDoPlano } from './useFrasesDoPlano';

const props = defineProps({
  // O que mostrar de cada versão: [texto ou nome do modelo ou assunto da 1, idem da 2].
  versoes: { type: Array, required: true },
  // { criterio, divisao, espera }
  regra: { type: Object, required: true },
  publico: { type: Number, default: 0 },
  // O plano do teste contado pelo servidor (recipient_previews), quando já chegou.
  plano: { type: Object, default: null },
});
const emit = defineEmits(['alterar']);

const NS = 'DUAS_VERSOES.RESUMO';
const NS_REVISAO = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t } = useI18n();
// A primeira frase começa por "Ao enviar, só 270 pessoas recebem agora", para não brigar com o "Enviar agora" e o
// "Vão receber 1.350" da revisão.
const frases = useFrasesDoPlano(
  computed(() => props.regra),
  computed(() => props.publico),
  false,
  true,
  computed(() => props.plano)
);
</script>

<template>
  <div
    class="flex flex-col gap-3 border-t border-n-weak py-4"
    data-resumo-duas-versoes
  >
    <div class="flex items-center justify-between gap-3">
      <p class="m-0 text-xs font-semibold uppercase text-n-slate-11">
        {{ t(`${NS}.TITULO`) }}
      </p>
      <Button
        :label="t(`${NS_REVISAO}.CHANGE`)"
        :aria-label="
          t(`${NS_REVISAO}.CHANGE_ARIA`, { block: t(`${NS}.TITULO`) })
        "
        variant="ghost"
        size="sm"
        class="!min-h-11 shrink-0"
        data-alterar-versoes
        @click="emit('alterar')"
      />
    </div>
    <ul class="m-0 grid list-none gap-2 p-0 sm:grid-cols-2">
      <li
        v-for="(texto, indice) in versoes"
        :key="indice"
        class="flex min-w-0 flex-col gap-1 rounded-xl bg-n-alpha-1 px-4 py-3"
        :data-resumo-versao="indice + 1"
      >
        <span class="text-xs font-semibold text-n-slate-11">
          {{ t('DUAS_VERSOES.MENSAGEM.VERSAO', { n: indice + 1 }) }}
        </span>
        <span class="whitespace-pre-wrap break-words text-sm text-n-slate-12">
          {{ texto }}
        </span>
      </li>
    </ul>
    <div class="flex flex-col gap-1">
      <p
        v-for="(frase, indice) in frases"
        :key="indice"
        class="m-0 break-words text-sm"
        :class="
          indice === 0 ? 'font-medium text-n-slate-12' : 'text-n-slate-11'
        "
      >
        {{ frase }}
      </p>
    </div>
  </div>
</template>
