<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import AgenteAvatar from './AgenteAvatar.vue';
import AgenteStatus from './AgenteStatus.vue';
import AgenteBotao from './AgenteBotao.vue';
import AgenteMenuMais from './AgenteMenuMais.vue';
import { ESTADO, estadoDoAgente } from '../utils/estadoDoAgente';

// #1181 (protótipo T02) — cartão do agente na lista.
// - Atendendo/Parado: o cartão inteiro abre o agente. Atendendo mostra onde responde (nome do canal
//   pela L2; sem a L2, só a contagem) e os números da semana pela L1 (sem a L1, a linha some).
// - Falta terminar: "Continuar" e o "⋯" com Excluir rascunho, só para quem gerencia.
// - Cotação: abre o módulo de cotação. Agente interno não fala de canal.
// `canais`: caixas da L2 deste agente, ou null quando a L2 não pôde ser lida.
const props = defineProps({
  agente: { type: Object, required: true },
  numeros: { type: Object, default: null },
  canais: { type: Array, default: null },
  podeGerenciar: { type: Boolean, default: false },
  // Endereço da página do agente (ou do módulo de cotação): abrir em outra aba continua funcionando.
  href: { type: String, required: true },
});

const emit = defineEmits(['abrir', 'continuar', 'excluir', 'abrirCotacao']);

const { t } = useI18n();
const estado = computed(() => estadoDoAgente(props.agente));
const nome = computed(
  () => props.agente.name || t('AGENTS.JORNADA.COMUM.NOVO_AGENTE')
);
const interno = computed(() => props.agente.actuation === 'internal');
const quantosCanais = computed(() => props.agente.channels_count || 0);
const rascunho = computed(() => estado.value === ESTADO.FALTA_TERMINAR);
const cotacao = computed(() => estado.value === ESTADO.COTACAO);
const atendendo = computed(() => estado.value === ESTADO.ATENDENDO);

const onde = computed(() => {
  const total = quantosCanais.value;
  if (!total) return t('AGENTS.JORNADA.CARTAO.ONDE_NENHUM');
  const nomeDoCanal = total === 1 ? props.canais?.[0]?.name : null;
  if (nomeDoCanal) {
    return t('AGENTS.JORNADA.CARTAO.ONDE_CANAL', { canal: nomeDoCanal });
  }
  return t('AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS', { n: total }, total);
});

const linha = computed(() => {
  if (cotacao.value) return t('AGENTS.JORNADA.CARTAO.COTACAO');
  if (atendendo.value) return null;
  // Agente interno nunca entra em canal (backend: agent_internal_not_connectable).
  return quantosCanais.value || interno.value
    ? t('AGENTS.JORNADA.CARTAO.PARADO')
    : t('AGENTS.JORNADA.CARTAO.PARADO_SEM_CANAL');
});

const semConversas = computed(
  () => !props.numeros?.respondidas && !props.numeros?.passadas
);

const aoClicar = evento => {
  // Ctrl, Cmd, Shift ou o botão do meio abrem em outra aba pelo próprio link.
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button) {
    return;
  }
  evento.preventDefault();
  if (cotacao.value) emit('abrirCotacao', props.agente);
  else emit('abrir', props.agente);
};

const itensDoMenu = computed(() => [
  {
    chave: 'excluir',
    texto: t('AGENTS.JORNADA.CARTAO.EXCLUIR_RASCUNHO'),
    perigo: true,
  },
]);
</script>

<template>
  <li data-cartao class="list-none">
    <article
      v-if="rascunho"
      class="flex flex-col h-full gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div class="flex items-start gap-3">
        <AgenteAvatar :nome="nome" :src="agente.avatar_url || ''" />
        <div class="flex flex-col gap-1 grow min-w-0">
          <h2 class="m-0 text-base font-semibold truncate text-n-slate-12">
            {{ nome }}
          </h2>
          <AgenteStatus :estado="estado" />
        </div>
        <AgenteMenuMais
          v-if="podeGerenciar"
          :rotulo="t('AGENTS.JORNADA.CARTAO.MAIS_OPCOES', { nome })"
          :itens="itensDoMenu"
          @escolher="emit('excluir', agente)"
        />
      </div>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.CARTAO.RASCUNHO') }}
      </p>
      <AgenteBotao
        v-if="podeGerenciar"
        data-continuar
        variante="contorno"
        tamanho="lg"
        bloco
        class="mt-auto"
        icone-direita="i-lucide-arrow-right"
        :aria-label="t('AGENTS.JORNADA.CARTAO.CONTINUAR_ARIA', { nome })"
        @click="emit('continuar', agente)"
      >
        {{ t('AGENTS.JORNADA.CARTAO.CONTINUAR') }}
      </AgenteBotao>
    </article>
    <a
      v-else
      data-abrir
      :href="href"
      class="flex flex-col w-full h-full gap-3 p-5 transition shadow-sm text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 hover:ring-n-slate-7 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      @click="aoClicar"
    >
      <span class="flex items-start w-full gap-3">
        <AgenteAvatar
          :nome="nome"
          :src="agente.avatar_url || ''"
          :tom="atendendo ? 'atendendo' : 'neutro'"
        />
        <span class="flex flex-col gap-1 grow min-w-0">
          <h2 class="m-0 text-base font-semibold truncate text-n-slate-12">
            {{ nome }}
          </h2>
          <span class="flex flex-wrap items-center gap-1.5">
            <AgenteStatus :estado="estado" />
            <span
              v-if="interno"
              class="inline-flex items-center px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-slate-12"
            >
              {{ t('AGENTS.HUB.INTERNAL_BADGE') }}
            </span>
          </span>
        </span>
        <span
          class="mt-3 i-lucide-chevron-right size-5 text-n-slate-10 rtl:rotate-180"
          aria-hidden="true"
        />
      </span>
      <span v-if="linha" class="text-sm text-n-slate-12">{{ linha }}</span>
      <template v-if="atendendo && !interno">
        <span data-onde class="text-sm text-n-slate-12">{{ onde }}</span>
        <span
          v-if="numeros && semConversas"
          data-semana
          class="text-sm text-n-slate-11"
        >
          {{ t('AGENTS.JORNADA.CARTAO.SEMANA_VAZIA') }}
        </span>
        <span
          v-else-if="numeros"
          data-semana
          class="flex flex-col text-sm md:flex-row md:flex-wrap md:gap-x-2 text-n-slate-11"
        >
          <I18nT
            keypath="AGENTS.JORNADA.CARTAO.SEMANA_RESPONDIDAS"
            :plural="numeros.respondidas"
            tag="span"
            scope="global"
          >
            <template #n>
              <b class="text-base tabular-nums text-n-slate-12">{{
                numeros.respondidas
              }}</b>
            </template>
          </I18nT>
          <!-- No celular cada parte vai numa linha e o ponto some (.sep-dot do protótipo). -->
          <span
            data-separador
            aria-hidden="true"
            class="self-center hidden rounded-full md:block size-1 bg-n-slate-9"
          />
          <I18nT
            keypath="AGENTS.JORNADA.CARTAO.SEMANA_PASSADAS"
            :plural="numeros.passadas"
            tag="span"
            scope="global"
          >
            <template #n>
              <b class="text-base tabular-nums text-n-slate-12">{{
                numeros.passadas
              }}</b>
            </template>
          </I18nT>
        </span>
      </template>
    </a>
  </li>
</template>
