<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import { MODELOS, MODELO_DO_MEU_JEITO } from '../constants/modelos';

// #1366 (protótipo da Fase 2, rodada 3) — "Criar agente" em página inteira, no lugar da gaveta da
// lista. O agente normal é o destaque: os modelos e "Do meu jeito" seguem a criação de hoje (o canal
// é escolhido no fim, em Comece). Embaixo, discreto, "Precisa de outro tipo?": agente da equipe
// (secundário num canal que já tem quem atenda primeiro) ou ajuda outros agentes.
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const router = useRouter();
const NS = 'AGENTS.JORNADA.ONDE.ESCOLHER';
const comecando = ref(null);

const usar = chave => {
  if (comecando.value) return;
  comecando.value = chave;
  emit('escolher', { modelo: chave });
};

const OUTROS = [
  { tipo: 'equipe', icone: 'i-lucide-hand-helping', chave: 'EQUIPE' },
  { tipo: 'ajuda', icone: 'i-lucide-users', chave: 'AJUDA' },
];

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

      <AgentesHeroi :titulo="t(`${NS}.TITULO`)" :texto="t(`${NS}.TEXTO`)">
        <ul
          :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
          class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
        >
          <ModeloCartao
            v-for="modelo in MODELOS"
            :key="modelo.chave"
            :modelo="modelo"
            pode-usar
            :comecando="comecando === modelo.chave"
            :bloqueado="!!comecando && comecando !== modelo.chave"
            @usar="usar"
          />
        </ul>
        <p class="pt-5 m-0 border-t border-white/15">
          <button
            data-do-meu-jeito
            type="button"
            class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
            @click="usar(MODELO_DO_MEU_JEITO)"
          >
            {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO') }}
          </button>
        </p>
      </AgentesHeroi>

      <section
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
          <li v-for="outro in OUTROS" :key="outro.tipo">
            <button
              type="button"
              :data-outro="outro.tipo"
              class="flex items-start w-full h-full gap-3 p-4 text-start transition rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-8 hover:shadow-sm min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
              @click="emit('escolher', { tipo: outro.tipo })"
            >
              <span
                aria-hidden="true"
                class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                <span :class="outro.icone" class="size-5" />
              </span>
              <span class="flex flex-col gap-0.5 grow min-w-0">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t(`${NS}.${outro.chave}.TITULO`) }}
                </span>
                <span class="text-sm text-n-slate-11">
                  {{ t(`${NS}.${outro.chave}.TEXTO`) }}
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
