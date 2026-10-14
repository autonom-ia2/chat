<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import { MODELOS, MODELO_DO_MEU_JEITO } from '../constants/modelos';
import { ATUACAO_INTERNA_NA_QUERY } from '../constants/criacao';

// #1543 — "Criar agente" em página inteira, no lugar da gaveta da lista (protótipo aprovado na
// rodada 3, #1366/#1424). O agente normal é o destaque: os modelos e "Do meu jeito" seguem a criação
// de hoje (`?modelo=`; o canal é escolhido no fim, em Comece). Embaixo, discreto, "Precisa de outro
// tipo?" só com o Copiloto da equipe (`?atuacao=interno`, #1494/#1497).
// Os outros dois tipos do protótipo entram nesta mesma lista quando existirem de verdade, nunca
// antes como botão escondido ou desabilitado: "Agente da equipe" (tema 13, #1433/#1447) e "Ajuda
// outros agentes" (tema 14, #1434).
// A rota já exige autonomia_manage; quem só vê não chega aqui, mas a página também não oferece ação.
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const router = useRouter();
const podeGerenciar = useCanManage('autonomia_manage');
const NS = 'AGENTS.JORNADA.ESCOLHER';
const COPILOTO = 'copiloto';
const comecando = ref(null);

const escolher = (chave, query) => {
  if (comecando.value) return;
  comecando.value = chave;
  emit('escolher', query);
};

const usarModelo = chave => escolher(chave, { modelo: chave });
const usarCopiloto = () =>
  escolher(COPILOTO, { atuacao: ATUACAO_INTERNA_NA_QUERY });

const voltar = () => router.push({ name: 'autonomia_agents_index' });
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
          podeGerenciar ? t(`${NS}.TEXTO`) : t('AGENTS.JORNADA.HEROI.SO_VER')
        "
      >
        <ul
          :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
          class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
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
        <p v-if="podeGerenciar" class="pt-5 m-0 border-t border-white/15">
          <button
            data-do-meu-jeito
            type="button"
            class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
            @click="usarModelo(MODELO_DO_MEU_JEITO)"
          >
            {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO') }}
          </button>
        </p>
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
        <ul class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2">
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
