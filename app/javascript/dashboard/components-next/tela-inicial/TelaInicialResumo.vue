<script setup>
import { computed } from 'vue';

// #1801, opção 2 — o resumo do dia num herói escuro (o mesmo de Automações): números que
// levam à lista certa e uma ação, abrir a conversa que espera há mais tempo.
const props = defineProps({
  dados: { type: Object, required: true },
});

const numeros = computed(() => {
  const { esperando, semResponsavel, atrasadas } = props.dados;
  const lista = [
    {
      chave: 'ESPERAM',
      valor: esperando.length,
      fazer: props.dados.verMinhas,
    },
    {
      chave: 'SEM_RESPONSAVEL',
      valor: semResponsavel,
      fazer: props.dados.verSemResponsavel,
    },
  ];
  if (atrasadas === null) return lista;
  return [
    ...lista,
    {
      chave: 'FORA_DO_PRAZO',
      valor: atrasadas.length,
      alerta: atrasadas.length > 0,
      fazer: () =>
        atrasadas.length
          ? props.dados.abrir(atrasadas[0])
          : props.dados.verMinhas(),
    },
  ];
});
</script>

<template>
  <section
    data-tela-inicial="2"
    class="flex items-center justify-center w-full h-full p-4 overflow-auto bg-n-surface-1 md:p-10"
  >
    <div
      class="relative w-full max-w-3xl px-6 py-8 overflow-hidden text-white shadow-xl rounded-3xl bg-n-heroi ring-1 ring-inset ring-white/10 md:px-10 md:py-10"
    >
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
      />
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
      />
      <div class="relative flex flex-col gap-8">
        <header class="flex flex-col gap-2">
          <p
            class="mb-0 text-sm font-medium first-letter:uppercase text-white/60"
          >
            {{ dados.hoje }}
          </p>
          <h1
            class="mb-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-4xl"
          >
            {{
              dados.tudoEmDia
                ? $t('TELA_INICIAL.TUDO_EM_DIA')
                : $t('TELA_INICIAL.OPCAO_2.TITULO')
            }}
          </h1>
          <p class="mb-0 text-base text-white/75">
            {{
              $t(
                'TELA_INICIAL.OPCAO_2.COM_VOCE',
                { count: dados.comVoce },
                dados.comVoce
              )
            }}
          </p>
        </header>

        <ul
          class="grid gap-3 p-0 m-0 list-none"
          :class="numeros.length === 3 ? 'sm:grid-cols-3' : 'sm:grid-cols-2'"
        >
          <li v-for="numero in numeros" :key="numero.chave">
            <button
              type="button"
              :data-numero="numero.chave"
              class="flex flex-col items-start w-full h-full gap-1 p-5 transition text-start rounded-2xl bg-white/5 ring-1 ring-inset ring-white/10 hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              @click="numero.fazer()"
            >
              <span
                class="text-4xl font-semibold leading-none tabular-nums"
                :class="numero.alerta ? 'text-n-amber-9' : 'text-white'"
              >
                {{ numero.valor }}
              </span>
              <span class="flex items-center gap-1 text-sm text-white/75">
                {{ $t(`TELA_INICIAL.OPCAO_2.NUMEROS.${numero.chave}`) }}
                <span
                  class="i-lucide-chevron-right size-4 text-white/40 rtl:rotate-180"
                  aria-hidden="true"
                />
              </span>
            </button>
          </li>
        </ul>

        <div
          v-if="!dados.tudoEmDia"
          class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:gap-5"
        >
          <button
            type="button"
            data-abrir-proxima
            class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition bg-white min-h-12 rounded-xl text-n-heroi hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
            @click="dados.abrir(dados.proxima)"
          >
            {{ $t('TELA_INICIAL.ABRIR_PROXIMA') }}
            <span
              class="i-lucide-arrow-right size-5 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
          <p class="mb-0 text-sm text-white/60">
            {{
              $t('TELA_INICIAL.PROXIMA_ESPERA', {
                nome: dados.nomeDoCliente(dados.proxima),
                tempo: dados.esperaHa(dados.proxima),
              })
            }}
          </p>
        </div>
        <div v-else class="flex flex-col items-start gap-3">
          <button
            type="button"
            data-acao-do-vazio
            class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition bg-white min-h-12 rounded-xl text-n-heroi hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
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
    </div>
  </section>
</template>
