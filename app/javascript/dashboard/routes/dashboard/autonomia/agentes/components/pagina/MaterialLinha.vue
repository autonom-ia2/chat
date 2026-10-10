<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteMenuMais from '../AgenteMenuMais.vue';
import AgenteBotao from '../AgenteBotao.vue';
import { ehSite, estadoDaFonte, nomeDaFonte } from '../../utils/pagina';

// #1181 PR3 (protótipo srcRow, T09) — um arquivo ou site do agente: o nome e o estado em palavras
// (Lendo…, Pronto, Não consegui ler), sem nota, confiança nem percentual. Quem gerencia tem o "⋯"
// (Ler de novo, só para site; Tirar) e, no que não deu para ler, "Mandar outro".
const props = defineProps({
  fonte: { type: Object, required: true },
  nomeAgente: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
});

const emit = defineEmits(['lerDeNovo', 'tirar', 'mandarOutro']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.SABE';

const estado = computed(() => estadoDaFonte(props.fonte));
const site = computed(() => ehSite(props.fonte));
const nome = computed(() => nomeDaFonte(props.fonte));

const itens = computed(() => [
  ...(site.value ? [{ chave: 'ler', texto: t(`${NS}.LER_DE_NOVO`) }] : []),
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
      estado === 'falha'
        ? 'bg-n-amber-2 ring-n-amber-6'
        : 'bg-n-solid-1 ring-n-weak'
    "
  >
    <div class="flex items-center gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-lg place-items-center size-10 shrink-0 bg-n-slate-3 text-n-slate-11"
      >
        <span
          :class="site ? 'i-lucide-globe' : 'i-lucide-file-text'"
          class="size-5"
        />
      </span>
      <span class="flex flex-col min-w-0 grow">
        <span
          class="text-sm font-medium truncate text-n-slate-12"
          :title="nome"
        >
          {{ nome }}
        </span>
        <span
          data-estado-texto
          class="inline-flex items-center gap-1 text-xs"
          :class="{
            'text-n-slate-11': estado === 'lendo',
            'text-n-teal-11': estado === 'pronto',
            'text-n-amber-11': estado === 'falha',
          }"
        >
          <span
            v-if="estado === 'lendo'"
            aria-hidden="true"
            class="border-2 rounded-full size-3.5 border-n-slate-7 border-t-n-blue-11 motion-safe:animate-spin"
          />
          <span
            v-else
            aria-hidden="true"
            class="size-3.5"
            :class="
              estado === 'pronto' ? 'i-lucide-check' : 'i-lucide-triangle-alert'
            "
          />
          <template v-if="estado === 'lendo'">{{ t(`${NS}.LENDO`) }}</template>
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
        @escolher="escolher"
      />
    </div>
    <div v-if="estado === 'falha'" class="flex flex-col items-start gap-2">
      <p class="m-0 text-sm text-n-slate-12">
        {{ t(`${NS}.FALHA_TEXTO`, { nome: nomeAgente }) }}
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
  </li>
</template>
