<script setup>
// Enquete com a cara do WhatsApp (#1702): a pergunta em negrito, "Selecione uma (ou mais)
// opção(ões)", e cada opção com o círculo (marcado em verde com ✓ quando alguém
// escolheu), o título, a contagem à direita e a barra verde da proporção. Embaixo de
// uma linha fina, "Ver votos" abre quem votou em quê, ali mesmo. A equipe só lê: votar
// é no celular (a API não vota).
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import { SENDER_TYPES } from '../../message/constants';
import { useFuso } from '../pele';
import { horaDaMensagem, idiomaDoPainel } from '../dataDaConversa';
import { apurarEnquete, totalDeEleitores } from './enquete';

const { content, contentAttributes } = useMessageContext();
const { t, locale } = useI18n();
const fuso = useFuso();
const conversa = useMapGetter('getSelectedChat');

// O conector WAHA (#1709) grava a pergunta no texto da mensagem e `multiple`; a
// Cloud/robô pode mandar `name` e `multiple_answers`. Vale o que vier.
const enquete = computed(() => {
  const rica = contentAttributes.value?.richMessage || {};
  return {
    pergunta: rica.name || content.value || '',
    varias: Boolean(rica.multipleAnswers ?? rica.multiple),
  };
});
const opcoes = computed(() => apurarEnquete(contentAttributes.value));
const eleitores = computed(() => totalDeEleitores(contentAttributes.value));

const instrucao = computed(() =>
  enquete.value.varias
    ? t('CONVERSA_CANAL.ENQUETE.VARIAS')
    : t('CONVERSA_CANAL.ENQUETE.UMA')
);

const votos = n => t('CONVERSA_CANAL.ENQUETE.VOTOS', { n }, n);

const quemVotou = voto => {
  if (voto.senderType === SENDER_TYPES.CONTACT) {
    return (
      conversa.value?.meta?.sender?.name || t('CONVERSA_CANAL.REACOES.CLIENTE')
    );
  }
  return t('CONVERSA_CANAL.REACOES.EQUIPE');
};
const horaDoVoto = voto => {
  const quando = Math.floor(Date.parse(voto.at) / 1000);
  if (!Number.isFinite(quando)) return '';
  return horaDaMensagem(quando, fuso.value, idiomaDoPainel(locale.value));
};

// A barra é um desenho (SVG): a largura proporcional vai no atributo, sem estilo inline.
const largura = opcao => `${Math.round(opcao.fracao * 100)}%`;

const aberto = ref(false);
const idVotos = `votos-${useId()}`;
</script>

<template>
  <BaseBubble class="!px-[9px] !pt-[6px] !pb-0" data-bubble-name="enquete">
    <div class="w-[300px] max-w-full" data-enquete-do-whatsapp>
      <p class="m-0 text-[15px] leading-5 font-semibold break-words">
        {{ enquete.pergunta }}
      </p>
      <p
        class="m-0 mt-1 flex items-center gap-1 text-[13px] text-[#666666] dark:text-[#A7A8A8]"
      >
        <span
          class="size-3.5 shrink-0"
          :class="enquete.varias ? 'i-ph-checks-bold' : 'i-ph-check-bold'"
          aria-hidden="true"
        />
        {{ instrucao }}
      </p>
      <ul class="m-0 mt-3 flex flex-col gap-3.5 list-none" role="list">
        <li
          v-for="opcao in opcoes"
          :key="opcao.id"
          class="flex items-start gap-2.5"
          data-opcao-da-enquete
        >
          <span class="sr-only">
            {{
              t('CONVERSA_CANAL.ENQUETE.OPCAO', {
                titulo: opcao.titulo,
                votos: votos(opcao.votos),
              })
            }}
          </span>
          <span
            class="grid place-content-center size-5 mt-px shrink-0 rounded-full border-2"
            :class="
              opcao.votos
                ? 'border-[#21C063] bg-[#21C063] text-white'
                : 'border-[#8C8C8C] dark:border-[#A7A8A8]'
            "
            aria-hidden="true"
            :data-escolhida="opcao.votos > 0"
          >
            <span v-if="opcao.votos" class="i-ph-check-bold size-3" />
          </span>
          <span class="flex-1 min-w-0" aria-hidden="true">
            <span class="flex items-start justify-between gap-2">
              <span class="text-[14.2px] leading-[19px] break-words">
                {{ opcao.titulo }}
              </span>
              <span
                class="text-[13px] tabular-nums text-[#666666] dark:text-[#A7A8A8]"
              >
                {{ opcao.votos }}
              </span>
            </span>
            <svg
              class="block w-full h-[6px] mt-1.5"
              preserveAspectRatio="none"
              data-barra-da-opcao
            >
              <rect
                width="100%"
                height="6"
                rx="3"
                class="fill-[#0A0A0A]/10 dark:fill-white/10"
              />
              <rect
                v-if="opcao.votos"
                :width="largura(opcao)"
                height="6"
                rx="3"
                class="fill-[#21C063]"
              />
            </svg>
          </span>
        </li>
      </ul>
      <div
        v-if="aberto"
        :id="idVotos"
        class="mt-3 flex flex-col gap-2 text-[13px]"
        data-votos-da-enquete
      >
        <p v-if="!eleitores" class="m-0 text-[#666666] dark:text-[#A7A8A8]">
          {{ t('CONVERSA_CANAL.ENQUETE.SEM_VOTOS') }}
        </p>
        <template v-for="opcao in opcoes" :key="opcao.id">
          <div v-if="opcao.votos">
            <p class="m-0 font-medium">
              {{
                t('CONVERSA_CANAL.ENQUETE.TITULO_E_VOTOS', {
                  titulo: opcao.titulo,
                  votos: votos(opcao.votos),
                })
              }}
            </p>
            <ul class="m-0 list-none">
              <li
                v-for="voto in opcao.quem"
                :key="`${voto.senderType}-${voto.senderId}`"
                class="flex justify-between gap-2 text-[#3B3B3B] dark:text-[#D1D7DB]"
              >
                <span class="truncate">{{ quemVotou(voto) }}</span>
                <span class="shrink-0 text-[#666666] dark:text-[#A7A8A8]">
                  {{ horaDoVoto(voto) }}
                </span>
              </li>
            </ul>
          </div>
        </template>
      </div>
      <button
        type="button"
        class="w-[calc(100%+18px)] -mx-[9px] h-11 mt-6 border-t border-[#000]/10 dark:border-white/10 text-[14px] font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#000]/[0.03] dark:hover:bg-white/[0.03] focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#25D366]"
        :aria-expanded="aberto"
        :aria-controls="idVotos"
        data-ver-votos
        @click="aberto = !aberto"
      >
        {{
          aberto
            ? t('CONVERSA_CANAL.ENQUETE.OCULTAR_VOTOS')
            : t('CONVERSA_CANAL.ENQUETE.VER_VOTOS')
        }}
      </button>
    </div>
  </BaseBubble>
</template>
