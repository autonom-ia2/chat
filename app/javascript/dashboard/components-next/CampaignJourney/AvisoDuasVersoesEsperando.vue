<script setup>
// #3099 (D5) — na lista de Campanhas: as campanhas cujo teste das duas versões terminou no "eu escolho" e esperam
// alguém escolher a versão que vai para o resto. Cada uma diz quantas pessoas esperam, até quando dá para escolher
// (depois disso a versão 1 vai sozinha) e leva ao Resultado, onde fica o "Mandar esta para os outros".
// Também as campanhas em que, passada a espera, ninguém do teste recebeu (`motivo: 'sem_envio'`): o aviso leva ao
// Resultado para a pessoa ver o que aconteceu, e diz até quando a versão 1 vai para o resto.
//
// A lista vem do overview (`duas_versoes_esperando`, CampaignJourney::DuasVersoes::Esperando). Sem nenhuma, ou sem
// conseguir ler, o aviso não aparece: a lista de Campanhas continua igual.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import { resultRoute } from 'dashboard/components-next/CampaignResult/resultMetrics';
import { formatNumber, toLocaleTag } from './localeTag';
import { useOnEnter } from './useOnEnter';

// O menor período do overview: a lista das que esperam não depende dele.
const DIAS = 7;
const NS = 'DUAS_VERSOES.AVISO_LISTA';

const { t, locale } = useI18n();
const campanhas = ref([]);

const quando = epoch =>
  new Intl.DateTimeFormat(toLocaleTag(locale.value), {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(epoch * 1000));

const linha = campanha => {
  const semEnvio = campanha.motivo === 'sem_envio';
  const resto = formatNumber(campanha.resto ?? 0, locale.value);
  return {
    chave: `${campanha.channel}:${campanha.id}`,
    semEnvio,
    texto: t(semEnvio ? `${NS}.TEXTO_SEM_ENVIO` : `${NS}.TEXTO`, {
      nome: campanha.name,
      resto,
    }),
    sozinha: campanha.vai_sozinha_em
      ? t(semEnvio ? `${NS}.SOZINHA_SEM_ENVIO` : `${NS}.SOZINHA`, {
          data: quando(campanha.vai_sozinha_em),
          resto,
        })
      : '',
    botao: t(semEnvio ? `${NS}.VER` : `${NS}.ESCOLHER`),
    aria: t(semEnvio ? `${NS}.VER_ARIA` : `${NS}.ESCOLHER_ARIA`, {
      nome: campanha.name,
    }),
    rota: resultRoute(campanha.channel, campanha.id),
  };
};

const titulo = computed(() =>
  campanhas.value.some(campanha => campanha.semEnvio)
    ? t(`${NS}.TITULO_ATENCAO`)
    : t(`${NS}.TITULO`)
);

const carregar = async () => {
  try {
    const { data } = await CampaignResultsAPI.getOverview({ days: DIAS });
    campanhas.value = (data?.payload?.duas_versoes_esperando || []).map(linha);
  } catch {
    campanhas.value = [];
  }
};

useOnEnter(carregar);
</script>

<template>
  <!-- Sem campanha esperando, o embrulho não ocupa lugar (display: contents). -->
  <div class="contents">
    <section
      v-if="campanhas.length"
      class="mb-5 flex flex-col gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 px-5 py-4"
      data-aviso-duas-versoes
    >
      <h2
        class="m-0 flex items-center gap-2 text-sm font-semibold text-n-amber-12"
      >
        <span class="i-lucide-hand size-4 shrink-0" aria-hidden="true" />
        {{ titulo }}
      </h2>
      <ul class="m-0 flex list-none flex-col gap-3 p-0">
        <li
          v-for="campanha in campanhas"
          :key="campanha.chave"
          class="flex flex-wrap items-center justify-between gap-3"
          :data-esperando="campanha.chave"
        >
          <div class="flex min-w-0 flex-col gap-0.5 text-sm text-n-amber-12">
            <span class="break-words">{{ campanha.texto }}</span>
            <span v-if="campanha.sozinha" class="text-xs">
              {{ campanha.sozinha }}
            </span>
          </div>
          <router-link
            :to="campanha.rota"
            :aria-label="campanha.aria"
            class="inline-flex min-h-11 shrink-0 items-center rounded-xl bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-amber-7 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          >
            {{ campanha.botao }}
          </router-link>
        </li>
      </ul>
    </section>
  </div>
</template>
