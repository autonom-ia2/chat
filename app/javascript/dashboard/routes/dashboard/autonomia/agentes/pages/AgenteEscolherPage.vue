<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import RamosProntos from '../components/RamosProntos.vue';
import ProntosParaContratar from '../components/ProntosParaContratar.vue';
import { MODELOS, MODELO_DO_MEU_JEITO } from '../constants/modelos';
import { MODELOS_CONTRATADOS } from '../constants/contratados';
import {
  ATUACAO_INTERNA_NA_QUERY,
  PAPEL_AJUDANTE_NA_QUERY,
  PAPEL_AREA_NA_QUERY,
} from '../constants/criacao';
import { useFase2 } from '../composables/useFase2';
import { useRamosDeSeguro } from '../composables/useRamosDeSeguro';
import { useContratados } from '../composables/useContratados';

// #1543 — "Criar agente" em página inteira, no lugar da gaveta da lista (protótipo aprovado na
// rodada 3, #1366/#1424). O agente normal é o destaque: os modelos e "Do meu jeito" seguem a criação
// de hoje (`?modelo=`; o canal é escolhido no fim, em Comece). Embaixo, discreto, "Precisa de outro
// tipo?" só com o Copiloto da equipe (`?atuacao=interno`, #1494/#1497).
// #1433 (tema 13): "Agente da equipe" (`?papel=area`), só com a Fase 2 ligada na conta (piloto): fica
// num canal que já tem agente principal e recebe a conversa quando alguém passa.
// Tema 14 (#1434): "Ajuda outros agentes" (`?papel=ajudante`), também só com a Fase 2, na ordem do
// protótipo (depois do agente da equipe): responde só para outro agente, nunca para o cliente.
// A rota já exige autonomia_manage; quem só vê não chega aqui, mas a página também não oferece ação.
// #2881 — "Prontos para o seu ramo": em conta de seguros com os agentes prontos liberados (quem diz é o servidor,
// useRamosDeSeguro), a fileira vem primeiro, dentro do herói, e cada cartão leva `?ramo=<chave>`. Os três modelos
// gerais continuam embaixo, iguais. Sem ramo liberado, a página é a de sempre.
// #3214 — "Escrever as instruções com as minhas palavras", logo abaixo de "Do meu jeito" (`?escrever=1`).
// #3211 — "Vendem sozinhos" (mockup aprovado, estado 01): os agentes prontos que a corretora contrata vêm primeiro,
// dentro do herói e acima dos ramos (quem diz quais é o servidor, useContratados). O cartão leva à página do modelo
// (autonomia_contratado_modelo), e não à criação: contratar pede os dados da corretora lá.
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const router = useRouter();
const podeGerenciar = useCanManage('autonomia_manage');
const fase2 = useFase2();
const NS = 'AGENTS.JORNADA.ESCOLHER';
const COPILOTO = 'copiloto';
const EQUIPE = 'equipe';
const AJUDANTE = 'ajudante';
const ESCREVER = 'escrever';
const RAMOS = 'AGENTS.JORNADA.RAMOS';
const comecando = ref(null);
const { ramos } = useRamosDeSeguro();
const comRamos = computed(() => ramos.value.length > 0);
const { modelos: liberados } = useContratados();
const contratados = computed(() =>
  liberados.value.filter(modelo => MODELOS_CONTRATADOS.includes(modelo))
);
// Com "Vendem sozinhos" em cima, o bloco seguinte do herói começa com a linha divisória.
const DIVISAO = 'pt-6 border-t border-white/15';

const escolher = (chave, query) => {
  if (comecando.value) return;
  comecando.value = chave;
  emit('escolher', query);
};

const usarModelo = chave => escolher(chave, { modelo: chave });
const usarRamo = chave => escolher(chave, { ramo: chave });
const usarCopiloto = () =>
  escolher(COPILOTO, { atuacao: ATUACAO_INTERNA_NA_QUERY });
const usarEquipe = () => escolher(EQUIPE, { papel: PAPEL_AREA_NA_QUERY });
const usarAjudante = () =>
  escolher(AJUDANTE, { papel: PAPEL_AJUDANTE_NA_QUERY });
const usarEscrever = () => escolher(ESCREVER, { escrever: '1' });

const voltar = () => router.push({ name: 'autonomia_agents_index' });
const abrirContratado = modelo =>
  router.push({ name: 'autonomia_contratado_modelo', params: { modelo } });
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      data-escolher-agente
      class="flex flex-col w-full max-w-5xl gap-8 px-4 py-6 mx-auto md:px-6"
    >
      <button
        type="button"
        data-voltar-lista
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('AGENTS.JORNADA.CRIAR.VOLTAR') }}
      </button>

      <AgentesHeroi
        :titulo="t(`${NS}.TITULO`)"
        :texto="
          podeGerenciar
            ? t(comRamos ? `${RAMOS}.TEXTO_DA_PAGINA` : `${NS}.TEXTO`)
            : t('AGENTS.JORNADA.HEROI.SO_VER')
        "
      >
        <ProntosParaContratar
          v-if="contratados.length"
          :modelos="contratados"
          :pode-usar="podeGerenciar"
          @abrir="abrirContratado"
        />
        <div v-if="comRamos" :class="contratados.length ? DIVISAO : ''">
          <RamosProntos
            :ramos="ramos"
            :pode-usar="podeGerenciar"
            :comecando="comecando"
            @usar="usarRamo"
          />
        </div>
        <ul
          :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
          class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
          :class="contratados.length && !comRamos ? DIVISAO : ''"
        >
          <ModeloCartao
            v-for="modelo in MODELOS"
            :key="modelo.chave"
            :modelo="modelo"
            :pode-usar="podeGerenciar"
            :comecando="comecando === modelo.chave"
            :bloqueado="!!comecando && comecando !== modelo.chave"
            @usar="usarModelo"
          />
        </ul>
        <div
          v-if="podeGerenciar"
          class="flex flex-col gap-3 pt-5 border-t border-white/15"
        >
          <p class="flex flex-col m-0">
            <button
              data-do-meu-jeito
              type="button"
              aria-describedby="do-meu-jeito-escolher-texto"
              class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              @click="usarModelo(MODELO_DO_MEU_JEITO)"
            >
              {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO') }}
            </button>
            <span
              id="do-meu-jeito-escolher-texto"
              class="text-sm text-white/80"
            >
              {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO_TEXTO') }}
            </span>
          </p>
          <p class="flex flex-col m-0">
            <button
              data-escrever-instrucoes
              type="button"
              aria-describedby="escrever-escolher-texto"
              class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              @click="usarEscrever"
            >
              {{ t('AGENTS.JORNADA.MODELOS.ESCREVER_INSTRUCOES') }}
            </button>
            <span id="escrever-escolher-texto" class="text-sm text-white/80">
              {{ t('AGENTS.JORNADA.MODELOS.ESCREVER_INSTRUCOES_TEXTO') }}
            </span>
          </p>
        </div>
      </AgentesHeroi>

      <section
        v-if="podeGerenciar"
        data-outro-tipo
        aria-labelledby="outro-tipo-titulo"
        class="flex flex-col gap-3"
      >
        <div class="flex flex-col gap-1">
          <h2
            id="outro-tipo-titulo"
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${NS}.OUTRO_TIPO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.OUTRO_TEXTO`) }}
          </p>
        </div>
        <ul
          class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2"
          :class="fase2 ? 'lg:grid-cols-3' : ''"
        >
          <li v-if="fase2">
            <button
              type="button"
              data-outro="equipe"
              data-agente-da-equipe
              :disabled="!!comecando && comecando !== EQUIPE"
              class="flex items-start w-full h-full gap-3 p-4 transition text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-8 hover:shadow-sm min-h-11 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
              @click="usarEquipe"
            >
              <span
                aria-hidden="true"
                class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-hand-helping size-5" />
              </span>
              <span class="flex flex-col gap-0.5 grow min-w-0">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t(`${NS}.EQUIPE.TITULO`) }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t(`${NS}.EQUIPE.TEXTO`) }}
                </span>
              </span>
              <span
                class="self-center i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                aria-hidden="true"
              />
            </button>
          </li>
          <li v-if="fase2">
            <button
              type="button"
              data-outro="ajudante"
              data-ajudante
              :disabled="!!comecando && comecando !== AJUDANTE"
              class="flex items-start w-full h-full gap-3 p-4 transition text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-8 hover:shadow-sm min-h-11 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
              @click="usarAjudante"
            >
              <span
                aria-hidden="true"
                class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-bot size-5" />
              </span>
              <span class="flex flex-col gap-0.5 grow min-w-0">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t(`${NS}.AJUDA.TITULO`) }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t(`${NS}.AJUDA.TEXTO`) }}
                </span>
              </span>
              <span
                class="self-center i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                aria-hidden="true"
              />
            </button>
          </li>
          <li>
            <button
              type="button"
              data-outro="copiloto"
              data-copiloto
              :disabled="!!comecando && comecando !== COPILOTO"
              class="flex items-start w-full h-full gap-3 p-4 transition text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-8 hover:shadow-sm min-h-11 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
              @click="usarCopiloto"
            >
              <span
                aria-hidden="true"
                class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-users size-5" />
              </span>
              <span class="flex flex-col gap-0.5 grow min-w-0">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t('AGENTS.JORNADA.MODELOS.COPILOTO') }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t('AGENTS.JORNADA.MODELOS.COPILOTO_TEXTO') }}
                </span>
              </span>
              <span
                class="self-center i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
