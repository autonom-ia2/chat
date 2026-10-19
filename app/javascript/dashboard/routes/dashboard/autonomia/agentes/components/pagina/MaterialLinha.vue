<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteMenuMais from '../AgenteMenuMais.vue';
import AgenteBotao from '../AgenteBotao.vue';
import { ehSite, estadoDaFonte, nomeDaFonte } from '../../utils/pagina';
import { ehFotoDaBase } from '../../utils/estadoDoMaterial';

// #1181 PR3 (protótipo srcRow, T09) — um arquivo ou site do agente: o nome e o estado em palavras
// (Lendo…, Pronto, Não consegui ler), sem nota, confiança nem percentual. Quem gerencia tem o "⋯"
// (Ler de novo, só para site; Tirar) e, no que não deu para ler, "Mandar outro".
// #1503 — a caixa da base na criação reaproveita a linha: o estado vem pronto (`estado`, do material
// da conversa), sem "Ler de novo" (`podeReler`), com o texto do problema dela (`problema`) e a
// confirmação de tirar no slot, dentro da própria linha. Lá o nome quebra em até duas linhas
// (`nomeEmDuasLinhas`): a coluna da criação é estreita; na gaveta da página ele continua numa linha.
const props = defineProps({
  fonte: { type: Object, required: true },
  nomeAgente: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  // #1369 — "Ler de novo" pedido e o site ainda não voltou da leitura: mostra "Lendo…".
  relendo: { type: Boolean, default: false },
  // Estado já decidido por quem usa ('lendo' | 'pronto' | 'falha'); vazio = lido da fonte.
  // #1426 — na Fase 2 a gaveta manda o estado real (utils/estadoDoMaterial): também 'revisando' (lido, mas a revisão
  // não terminou: ainda não é Pronto) e 'atencao' ("Precisa de você": a revisão não aprovou e o agente não o usa).
  estado: { type: String, default: '' },
  podeReler: { type: Boolean, default: true },
  // Texto no lugar de "{nome} ainda não usa este…" (ex.: arquivo grande demais).
  problema: { type: String, default: '' },
  nomeEmDuasLinhas: { type: Boolean, default: false },
  // #1426 — arquivo ou foto parado em "Lendo…" ou "Revisando…" além do teto da releitura (o worker caiu): libera
  // "Ler de novo".
  relerParado: { type: Boolean, default: false },
});

const emit = defineEmits(['lerDeNovo', 'tirar', 'mandarOutro']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.SABE';

const estado = computed(() => {
  if (props.relendo) return 'lendo';
  return props.estado || estadoDaFonte(props.fonte);
});
const site = computed(() => ehSite(props.fonte));
const foto = computed(() => ehFotoDaBase(props.fonte));
const icone = computed(() => {
  if (site.value) return 'i-lucide-globe';
  return foto.value ? 'i-lucide-image' : 'i-lucide-file-text';
});
const girando = computed(() => ['lendo', 'revisando'].includes(estado.value));
const amarelo = computed(() => ['falha', 'atencao'].includes(estado.value));
const ICONE_DO_ESTADO = {
  pronto: 'i-lucide-check',
  atencao: 'i-lucide-hand',
  falha: 'i-lucide-triangle-alert',
};
const nome = computed(() => nomeDaFonte(props.fonte));
// #1426 — o que aparece embaixo da linha amarela: o motivo da revisão (curto e em linguagem simples, escrito pelo
// Revisor) ou, sem ele, o texto padrão; o cartão "um problema por vez" vem no PR 2.
const textoDoProblema = computed(() => {
  if (estado.value === 'atencao') {
    return (
      props.fonte.review?.reason ||
      t(`${NS}.ATENCAO_TEXTO`, { nome: props.nomeAgente })
    );
  }
  return props.problema || t(`${NS}.FALHA_TEXTO`, { nome: props.nomeAgente });
});

const itens = computed(() => [
  ...((site.value && props.podeReler) || props.relerParado
    ? [{ chave: 'ler', texto: t(`${NS}.LER_DE_NOVO`) }]
    : []),
  { chave: 'tirar', texto: t(`${NS}.TIRAR`), perigo: true },
]);

const escolher = chave => {
  if (chave === 'ler') emit('lerDeNovo', props.fonte);
  else emit('tirar', props.fonte);
};
</script>

<template>
  <li
    data-fonte
    :data-estado="estado"
    class="flex flex-col gap-2 p-3 rounded-xl ring-1 ring-inset"
    :class="
      amarelo ? 'bg-n-amber-2 ring-n-amber-6' : 'bg-n-solid-1 ring-n-weak'
    "
  >
    <div class="flex items-center gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-lg place-items-center size-10 shrink-0 bg-n-slate-3 text-n-slate-11"
      >
        <span :class="icone" class="size-5" />
      </span>
      <span class="flex flex-col min-w-0 grow">
        <span
          class="text-sm font-medium text-n-slate-12"
          :class="
            nomeEmDuasLinhas
              ? 'line-clamp-2 [overflow-wrap:anywhere]'
              : 'truncate'
          "
          :title="nome"
        >
          {{ nome }}
        </span>
        <!-- #1369 — o estado é anunciado quando muda (Lendo…, Pronto); o aria-busy fica no "⋯", fora
             da região viva, para não segurar o anúncio. -->
        <span
          data-estado-texto
          role="status"
          aria-live="polite"
          class="inline-flex items-center gap-1 text-xs"
          :class="{
            'text-n-slate-11': girando,
            'text-n-teal-11': estado === 'pronto',
            'text-n-amber-11': amarelo,
          }"
        >
          <span
            v-if="girando"
            aria-hidden="true"
            class="border-2 rounded-full size-3.5 border-n-slate-7 border-t-n-blue-11 motion-safe:animate-spin"
          />
          <span
            v-else
            aria-hidden="true"
            class="size-3.5"
            :class="ICONE_DO_ESTADO[estado]"
          />
          <template v-if="estado === 'lendo'">
            {{ foto ? t(`${NS}.LENDO_FOTO`) : t(`${NS}.LENDO`) }}
          </template>
          <template v-else-if="estado === 'revisando'">
            {{ t(`${NS}.REVISANDO`) }}
          </template>
          <template v-else-if="estado === 'atencao'">
            {{ t(`${NS}.ATENCAO`) }}
          </template>
          <template v-else-if="estado === 'pronto'">
            {{ t(`${NS}.PRONTO`) }}
          </template>
          <template v-else>
            {{ site ? t(`${NS}.FALHA_SITE`) : t(`${NS}.FALHA_ARQUIVO`) }}
          </template>
        </span>
      </span>
      <AgenteMenuMais
        v-if="podeGerenciar"
        :rotulo="t(`${NS}.MAIS_DE`, { nome })"
        :itens="itens"
        :aria-busy="relendo ? 'true' : undefined"
        @escolher="escolher"
      />
    </div>
    <div v-if="amarelo" class="flex flex-col items-start gap-2">
      <p data-problema class="m-0 text-sm text-n-slate-12">
        {{ textoDoProblema }}
      </p>
      <AgenteBotao
        v-if="podeGerenciar"
        data-mandar-outro
        variante="contorno"
        @click="emit('mandarOutro', fonte)"
      >
        {{ t(`${NS}.MANDAR_OUTRO`) }}
      </AgenteBotao>
    </div>
    <slot />
  </li>
</template>
