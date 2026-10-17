<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { nomeSemExtensao } from '../utils/nomeDoArquivo';

// #1181 — celular no estilo WhatsApp: balões do cliente (direita, verde) e do agente (esquerda).
// Serve ao exemplo dos modelos (mini, com o selo "Exemplo") e ao teste (tamanho cheio, com cabeçalho
// e aria-live para anunciar a resposta). Embaixo da resposta, "Usou: <arquivo sem extensão>" quando o
// agente se apoiou num arquivo: quebra dentro do balão, no máximo 2 linhas, nome inteiro no title.
// Nunca mostra confiança, nota ou percentual.
// 'equipe' (#1494) é quem pergunta ao Copiloto da equipe: fica à direita, mas não como cliente.
// 'principal' (tema 14, #1434) é o agente principal que consulta o ajudante: também à direita.
// mensagens: [{ de: 'cliente' | 'equipe' | 'agente', texto, hora?, usou?: [nome do arquivo], fotos?: [url] }], ou
// { de: 'aviso', texto } para uma faixa no meio da conversa (ex.: "aqui passaria para a equipe").
// Slots (#1181 PR2, teste da criação): `acao` no cabeçalho, `depois` embaixo das mensagens (vazio,
// erro, "Respondeu errado?"), fora da região aria-live para só a conversa ser anunciada, e `rodape`
// fora da área de mensagens (perguntas prontas e campo).
const props = defineProps({
  mensagens: { type: Array, default: () => [] },
  digitando: { type: Boolean, default: false },
  tamanho: {
    type: String,
    default: 'normal',
    validator: v => ['mini', 'normal'].includes(v),
  },
  selo: { type: String, default: '' },
  rotuloSr: { type: String, default: '' },
  nome: { type: String, default: '' },
  estado: { type: String, default: '' },
});

const { t } = useI18n();

const mini = computed(() => props.tamanho === 'mini');
const inicial = computed(() =>
  (props.nome || '?').trim().charAt(0).toUpperCase()
);
const QUEM = {
  cliente: 'AGENTS.JORNADA.COMUM.CLIENTE',
  equipe: 'AGENTS.JORNADA.COMUM.EQUIPE',
  principal: 'AGENTS.JORNADA.COMUM.PRINCIPAL',
};
const quem = de => t(QUEM[de] || 'AGENTS.JORNADA.COMUM.AGENTE');
const BALAO = {
  cliente: 'self-end bg-[#D9FDD3] dark:bg-n-teal-4 rounded-ee-md',
  equipe: 'self-end bg-n-blue-3 rounded-ee-md',
  principal: 'self-end bg-n-iris-3 rounded-ee-md',
};
const classeDoBalao = de =>
  BALAO[de] || 'self-start bg-white dark:bg-n-solid-2 rounded-es-md';
</script>

<template>
  <div class="relative">
    <!-- Selo âmbar no canto de cima, dentro da tela (.phone-badge do protótipo). -->
    <span
      v-if="selo"
      data-selo
      aria-hidden="true"
      class="absolute z-10 px-2.5 py-0.5 text-xs font-bold rounded-full top-3 start-4 bg-n-amber-9 text-[#3D2A00]"
    >
      {{ selo }}
    </span>
    <!-- Moldura escura nos dois temas e fundo menta pontilhado (--device e --chat-bg do protótipo). -->
    <div
      class="relative overflow-hidden border-[6px] shadow-sm rounded-[1.75rem] border-[#1C2024] dark:border-[#0B0C0E] bg-[#EEF7F4] dark:bg-[#0F1A19] bg-[radial-gradient(rgba(0,112,95,0.07)_1.2px,transparent_1.3px)] dark:bg-[radial-gradient(rgba(11,216,182,0.05)_1.2px,transparent_1.3px)] bg-[length:12px_12px]"
      :class="mini ? 'max-w-72 mx-auto' : 'w-full max-w-sm mx-auto'"
    >
      <p v-if="rotuloSr" class="sr-only">{{ rotuloSr }}</p>
      <div
        v-if="!mini"
        class="flex items-center gap-2 px-3 py-2 bg-[#0D2344] text-white"
      >
        <span
          aria-hidden="true"
          class="grid font-semibold rounded-full place-items-center size-8 bg-white/20"
        >
          {{ inicial }}
        </span>
        <span class="flex flex-col min-w-0 grow">
          <span class="text-sm font-semibold truncate">{{ nome }}</span>
          <span v-if="estado" class="text-xs text-white/75">{{ estado }}</span>
        </span>
        <slot name="acao" />
      </div>
      <div
        class="flex flex-col gap-2 p-3"
        :class="[mini ? 'min-h-0' : 'min-h-64', selo ? 'pt-10' : '']"
        :aria-live="mini ? undefined : 'polite'"
      >
        <template v-for="(mensagem, indice) in mensagens" :key="indice">
          <p
            v-if="mensagem.de === 'aviso'"
            data-aviso
            class="flex items-start self-stretch gap-2 px-3 py-2 m-0 text-xs rounded-xl bg-n-amber-3 text-n-slate-12"
          >
            <span class="i-lucide-users size-4 shrink-0" aria-hidden="true" />
            <span>{{ mensagem.texto }}</span>
          </p>
          <div
            v-else
            :data-balao="mensagem.de"
            class="relative flex flex-col min-w-0 max-w-[85%] px-3 py-2 text-sm leading-relaxed shadow-sm rounded-2xl text-n-slate-12 [overflow-wrap:anywhere]"
            :class="classeDoBalao(mensagem.de)"
          >
            <span class="sr-only">{{
              t('AGENTS.JORNADA.COMUM.QUEM_DISSE', { quem: quem(mensagem.de) })
            }}</span>
            <img
              v-for="(foto, posicao) in mensagem.fotos || []"
              :key="posicao"
              :src="foto"
              :alt="t('AGENTS.JORNADA.COMUM.FOTO_ENVIADA')"
              class="object-cover w-full mb-1 rounded-xl max-h-48"
            />
            <span class="whitespace-pre-line">{{ mensagem.texto }}</span>
            <span
              v-if="mensagem.hora"
              class="self-end text-[0.6875rem] text-n-slate-11"
            >
              {{ mensagem.hora }}
            </span>
            <span
              v-for="arquivo in mensagem.usou || []"
              :key="arquivo"
              data-usou
              :title="arquivo"
              class="flex items-start min-w-0 gap-1 mt-1 text-xs text-n-slate-11"
            >
              <span
                class="i-lucide-file-text size-3.5 shrink-0 mt-px"
                aria-hidden="true"
              />
              <span class="min-w-0 line-clamp-2 [overflow-wrap:anywhere]">{{
                t('AGENTS.JORNADA.COMUM.USOU', {
                  arquivo: nomeSemExtensao(arquivo),
                })
              }}</span>
            </span>
          </div>
        </template>
        <div
          v-if="digitando"
          data-digitando
          class="relative flex items-center self-start gap-1 px-3 py-3 bg-white shadow-sm dark:bg-n-solid-2 rounded-2xl rounded-es-md"
        >
          <span class="sr-only">{{
            t('AGENTS.JORNADA.COMUM.ESCREVENDO')
          }}</span>
          <span
            v-for="ponto in 3"
            :key="ponto"
            aria-hidden="true"
            class="rounded-full size-1.5 bg-n-slate-9 motion-safe:animate-pulse"
          />
        </div>
      </div>
      <div v-if="$slots.depois" class="flex flex-col gap-2 px-3 pb-3">
        <slot name="depois" />
      </div>
      <slot name="rodape" />
    </div>
  </div>
</template>
