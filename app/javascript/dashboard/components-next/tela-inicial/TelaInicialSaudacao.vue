<script setup>
import { computed } from 'vue';

// #1801, opção 1 — saudação pelo nome e a próxima conversa. Tipografia forte e respiro;
// uma ação: abrir a conversa que espera há mais tempo.
const props = defineProps({
  dados: { type: Object, required: true },
});

const quantas = computed(() => props.dados.esperamVoce);
</script>

<template>
  <section
    data-tela-inicial="1"
    class="flex items-center justify-center w-full h-full px-6 py-12 overflow-auto bg-n-surface-1 md:px-16"
  >
    <div class="flex flex-col w-full max-w-xl gap-10">
      <header class="flex flex-col gap-4">
        <span class="w-12 h-1 rounded-full bg-n-brand" aria-hidden="true" />
        <p
          class="mb-0 text-sm font-medium first-letter:uppercase text-n-slate-10"
        >
          {{ dados.hoje }}
        </p>
        <h1
          class="mb-0 text-4xl font-semibold leading-tight tracking-tight md:text-5xl text-n-slate-12"
        >
          {{ dados.saudacao }}
        </h1>
      </header>

      <div v-if="dados.pronto && !dados.tudoEmDia" class="flex flex-col gap-8">
        <p class="mb-0 text-xl leading-relaxed md:text-2xl text-n-slate-11">
          <span class="font-semibold tabular-nums text-n-brand">
            {{ quantas }}
          </span>
          {{ $t('TELA_INICIAL.OPCAO_1.ESPERAM', { count: quantas }, quantas) }}
        </p>
        <div class="flex flex-col items-start gap-4">
          <button
            type="button"
            data-abrir-proxima
            class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold text-white transition shadow-lg min-h-12 rounded-xl bg-n-brand shadow-n-brand/20 hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            @click="dados.abrir(dados.proxima)"
          >
            {{ $t('TELA_INICIAL.ABRIR_PROXIMA') }}
            <span
              class="i-lucide-arrow-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <p class="flex items-center gap-2 mb-0 text-sm text-n-slate-10">
            <span class="i-lucide-clock-3 size-4" aria-hidden="true" />
            {{
              $t('TELA_INICIAL.PROXIMA_ESPERA', {
                nome: dados.nomeDoCliente(dados.proxima),
                tempo: dados.esperaHa(dados.proxima),
              })
            }}
          </p>
        </div>
      </div>

      <div v-else-if="dados.tudoEmDia" class="flex flex-col items-start gap-8">
        <p
          class="flex items-center gap-3 mb-0 text-xl leading-relaxed md:text-2xl text-n-slate-11"
        >
          <span
            class="grid rounded-full place-items-center size-9 shrink-0 bg-n-teal-3 text-n-teal-11"
            aria-hidden="true"
          >
            <span class="i-lucide-check size-5" />
          </span>
          {{ $t('TELA_INICIAL.OPCAO_1.TUDO_EM_DIA') }}
        </p>
        <button
          type="button"
          data-acao-do-vazio
          class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition min-h-12 rounded-xl text-n-slate-12 ring-1 ring-inset ring-n-strong hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          @click="dados.acaoDoVazio.fazer()"
        >
          {{ $t(`TELA_INICIAL.${dados.acaoDoVazio.rotulo}`) }}
          <span
            class="i-lucide-arrow-right size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
  </section>
</template>
