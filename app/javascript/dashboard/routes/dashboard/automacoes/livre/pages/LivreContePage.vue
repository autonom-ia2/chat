<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import AutomacaoHeroi from '../../components/AutomacaoHeroi.vue';
import { RECEITAS } from '../prototipo/dados';
import { fraseDoGatilho, fraseDoPasso, nomeDaEtapa } from '../prototipo/frases';

// #2414 F0 — "Conte com suas palavras": o mesmo herói de hoje. No protótipo o
// Guia não é chamado; a resposta dele é simulada (`?montou=1`) e leva ao mesmo
// editor "Confira" que as receitas e o "do zero" usam.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const montou = computed(() => route.query.montou === '1');
const etapa = computed(() => nomeDaEtapa(route.query.etapa));
const exemplo = RECEITAS.find(
  item => item.chave === 'ORCAMENTO_PARADO'
).receita;

const resumo = computed(() => [
  fraseDoGatilho(exemplo.gatilho, t),
  ...exemplo.passos.map(passo => fraseDoPasso(passo, t)),
]);

const pedir = () => router.replace({ query: { ...route.query, montou: '1' } });

const conferir = () =>
  router.push({
    name: 'automacoes_livre_nova',
    params: { accountId: route.params.accountId },
    query: { receita: 'ORCAMENTO_PARADO', guia: '1' },
  });

const voltar = () =>
  router.push({
    name: 'automacoes_livre_comecar',
    params: { accountId: route.params.accountId },
  });
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full max-w-5xl gap-6 px-5 py-8 pb-40 mx-auto md:px-8 md:py-10"
    >
      <button
        type="button"
        class="inline-flex items-center self-start gap-2 text-sm font-medium min-h-11 text-n-slate-11 hover:text-n-slate-12"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ $t('AUTOMACAO_LIVRE.VOLTAR') }}
      </button>
      <p
        v-if="etapa"
        data-contexto-etapa
        class="inline-flex items-center self-start gap-2 px-3 py-2 mb-0 text-sm rounded-xl bg-n-violet-3 text-n-violet-11"
      >
        <span class="i-lucide-square-kanban size-4" aria-hidden="true" />
        {{ $t('AUTOMACAO_LIVRE.CONTE.CONTEXTO_ETAPA', { etapa }) }}
      </p>
      <AutomacaoHeroi v-if="!montou" @pedir="pedir" @falar="pedir" />

      <section
        v-else
        data-guia-montou
        class="flex flex-col gap-5 p-6 border shadow-sm rounded-3xl border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center gap-3">
          <span
            class="grid rounded-xl place-items-center size-10 bg-n-heroi text-n-blue-6 dark:bg-n-heroi-escuro"
          >
            <span class="i-lucide-sparkles size-5" aria-hidden="true" />
          </span>
          <p class="mb-0 text-base font-semibold text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.CONTE.GUIA') }}
          </p>
        </div>
        <p
          class="self-end max-w-[80%] px-4 py-3 mb-0 text-[0.9375rem] rounded-2xl rounded-br-sm bg-n-blue-3 text-n-slate-12"
        >
          {{ $t('AUTOMACAO_LIVRE.CONTE.PEDIDO_EXEMPLO') }}
        </p>
        <div
          class="flex flex-col gap-3 max-w-[90%] px-4 py-3 rounded-2xl rounded-bl-sm bg-n-alpha-2 text-n-slate-12"
        >
          <p class="mb-0 text-[0.9375rem]">
            {{ $t('AUTOMACAO_LIVRE.CONTE.MONTEI') }}
          </p>
          <ol
            class="flex flex-col gap-1.5 ps-5 m-0 text-[0.9375rem] list-decimal"
          >
            <li v-for="(linha, indice) in resumo" :key="indice">
              {{ linha }}
            </li>
          </ol>
          <p class="mb-0 text-[0.9375rem]">
            {{ $t('AUTOMACAO_LIVRE.CONTE.CONFIRA') }}
          </p>
        </div>
        <Button
          data-conferir
          :label="$t('AUTOMACAO_LIVRE.CONTE.CONFERIR')"
          icon="i-lucide-list-checks"
          size="lg"
          class="self-start !min-h-12 !rounded-xl"
          @click="conferir"
        />
      </section>
    </div>
  </main>
</template>
