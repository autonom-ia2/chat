<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { RECEITAS } from '../prototipo/dados';
import { fraseDoGatilho } from '../prototipo/frases';
import { temSemVolta, usaIA } from '../prototipo/receita';

// #2414 F0 — "Receitas do seu negócio": as gerais e, à parte, as do pacote do
// segmento da conta (chegam prontas do servidor). Escolher abre o editor já
// preenchido; nada liga sozinho.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const gerais = computed(() => RECEITAS.filter(receita => !receita.pacote));
const doPacote = computed(() => RECEITAS.filter(receita => receita.pacote));
const nomeDoPacote = computed(() => doPacote.value[0]?.pacote.nome || '');

const titulo = receita =>
  receita.pacote
    ? receita.pacote.titulo
    : t(`AUTOMACAO_LIVRE.RECEITAS.${receita.chave}.TITULO`);
const texto = receita =>
  receita.pacote
    ? receita.pacote.texto
    : t(`AUTOMACAO_LIVRE.RECEITAS.${receita.chave}.TEXTO`);

const usar = receita =>
  router.push({
    name: 'automacoes_livre_nova',
    params: { accountId: route.params.accountId },
    query: { receita: receita.chave },
  });

const voltar = () =>
  router.push({
    name: 'automacoes_livre_comecar',
    params: { accountId: route.params.accountId },
  });

const grupos = computed(() => [
  { chave: 'GERAIS', receitas: gerais.value },
  { chave: 'PACOTE', receitas: doPacote.value },
]);
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full max-w-6xl gap-8 px-5 py-8 pb-40 mx-auto md:px-8 md:py-10"
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
      <header>
        <h1
          class="text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
        >
          {{ $t('AUTOMACAO_LIVRE.RECEITAS.TITULO') }}
        </h1>
        <p class="mt-2 mb-0 text-base md:text-lg text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.RECEITAS.SUBTITULO') }}
        </p>
      </header>

      <section
        v-for="grupo in grupos"
        :key="grupo.chave"
        class="flex flex-col gap-4"
      >
        <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
          {{
            $t(`AUTOMACAO_LIVRE.RECEITAS.GRUPO_${grupo.chave}`, {
              pacote: nomeDoPacote,
            })
          }}
        </h2>
        <ul class="grid gap-4 p-0 m-0 list-none md:grid-cols-2">
          <li v-for="receita in grupo.receitas" :key="receita.chave">
            <article
              :data-receita="receita.chave"
              class="flex flex-col h-full gap-4 p-5 border shadow-sm rounded-2xl bg-n-solid-1"
              :class="
                route.query.destaque === receita.chave
                  ? 'border-n-blue-8 ring-4 ring-n-blue-4'
                  : 'border-n-weak'
              "
            >
              <div class="flex items-start gap-4">
                <span
                  class="grid place-items-center size-12 shrink-0 rounded-xl"
                  :class="receita.tom"
                >
                  <span
                    class="size-6"
                    :class="receita.icone"
                    aria-hidden="true"
                  />
                </span>
                <div class="flex flex-col min-w-0 gap-1">
                  <h3 class="mb-0 text-base font-semibold text-n-slate-12">
                    {{ titulo(receita) }}
                  </h3>
                  <p class="mb-0 text-[0.9375rem] text-n-slate-11">
                    {{ texto(receita) }}
                  </p>
                </div>
              </div>
              <p
                class="px-3 py-2 mb-0 text-sm font-medium rounded-lg bg-n-blue-2 text-n-blue-11"
              >
                {{ fraseDoGatilho(receita.receita.gatilho, t) }}
              </p>
              <div class="flex flex-wrap gap-2">
                <span
                  v-if="receita.pacote"
                  class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  <span class="i-lucide-package size-3" aria-hidden="true" />
                  {{
                    $t('AUTOMACAO_LIVRE.ORIGEM.PACOTE', {
                      pacote: receita.pacote.nome,
                    })
                  }}
                </span>
                <span
                  v-if="temSemVolta(receita.receita)"
                  class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
                >
                  <span class="i-lucide-send size-3" aria-hidden="true" />
                  {{ $t('AUTOMACAO_LIVRE.RECEITAS.MANDA') }}
                </span>
                <span
                  v-if="usaIA(receita.receita)"
                  class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11"
                >
                  <span class="i-lucide-sparkles size-3" aria-hidden="true" />
                  {{ $t('AUTOMACAO_LIVRE.RECEITAS.USA_IA') }}
                </span>
              </div>
              <button
                type="button"
                :data-usar="receita.chave"
                class="inline-flex items-center self-start gap-2 px-4 mt-auto text-sm font-semibold text-white rounded-xl min-h-11 bg-n-brand hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
                @click="usar(receita)"
              >
                {{ $t('AUTOMACAO_LIVRE.RECEITAS.USAR') }}
                <span
                  class="i-lucide-arrow-right size-4 rtl:rotate-180"
                  aria-hidden="true"
                />
              </button>
            </article>
          </li>
        </ul>
      </section>
    </div>
  </main>
</template>
