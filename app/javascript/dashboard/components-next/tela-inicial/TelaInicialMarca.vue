<script setup>
import Hotkey from 'dashboard/components/base/Hotkey.vue';

// #1801, opção 3 — calma e de marca: o nome da conta, uma frase acolhedora, uma ação e,
// discretos, os atalhos. Sem nada esperando, comemora.
defineProps({
  dados: { type: Object, required: true },
});

const ATALHOS = [
  { tecla: 'K', rotulo: 'BUSCAR' },
  { tecla: '/', rotulo: 'VER_ATALHOS' },
];
</script>

<template>
  <section
    data-tela-inicial="3"
    class="flex flex-col items-center w-full h-full px-6 overflow-auto bg-gradient-to-b from-n-blue-2 via-n-surface-1 to-n-surface-1"
  >
    <div
      class="flex flex-col items-center justify-center flex-1 w-full max-w-md gap-6 py-12 text-center"
    >
      <span
        class="inline-flex items-center gap-2 py-1.5 ps-1.5 pe-4 rounded-full bg-n-solid-1 ring-1 ring-inset ring-n-weak shadow-sm"
      >
        <img
          v-if="dados.logo"
          :src="dados.logo"
          alt=""
          class="object-contain rounded-full size-7"
        />
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ dados.nomeDaConta }}
        </span>
      </span>

      <span
        v-if="dados.tudoEmDia"
        class="grid rounded-full place-items-center size-16 bg-n-teal-3 text-n-teal-11 ring-8 ring-n-teal-2"
        aria-hidden="true"
      >
        <span class="i-lucide-check size-8" />
      </span>

      <div class="flex flex-col gap-3">
        <h1
          class="mb-0 text-3xl font-semibold leading-tight tracking-tight md:text-4xl text-n-slate-12"
        >
          {{
            dados.tudoEmDia
              ? $t('TELA_INICIAL.TUDO_EM_DIA')
              : $t('TELA_INICIAL.OPCAO_3.ACOLHIDA', { nome: dados.nome })
          }}
        </h1>
        <p class="mb-0 text-base leading-relaxed md:text-lg text-n-slate-11">
          {{
            dados.tudoEmDia
              ? $t('TELA_INICIAL.OPCAO_3.TUDO_EM_DIA_TEXTO')
              : $t('TELA_INICIAL.OPCAO_3.TEXTO')
          }}
        </p>
      </div>

      <button
        v-if="dados.pronto && !dados.tudoEmDia"
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
      <button
        v-else-if="dados.tudoEmDia"
        type="button"
        data-acao-do-vazio
        class="inline-flex items-center justify-center gap-3 px-6 text-base font-semibold transition min-h-12 rounded-xl text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-strong hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        @click="dados.acaoDoVazio.fazer()"
      >
        {{ $t(`TELA_INICIAL.${dados.acaoDoVazio.rotulo}`) }}
      </button>
    </div>

    <ul class="hidden gap-6 p-0 pb-8 m-0 list-none md:flex" data-atalhos>
      <li
        v-for="atalho in ATALHOS"
        :key="atalho.tecla"
        class="flex items-center gap-2 text-xs text-n-slate-10"
      >
        <Hotkey
          custom-class="w-6 h-5 text-sm text-n-slate-11 outline outline-1 outline-n-container bg-n-alpha-2"
        >
          ⌘
        </Hotkey>
        <Hotkey
          custom-class="w-6 h-5 text-xs text-n-slate-11 outline outline-1 outline-n-container bg-n-alpha-2"
        >
          {{ atalho.tecla }}
        </Hotkey>
        {{ $t(`TELA_INICIAL.OPCAO_3.ATALHOS.${atalho.rotulo}`) }}
      </li>
    </ul>
  </section>
</template>
