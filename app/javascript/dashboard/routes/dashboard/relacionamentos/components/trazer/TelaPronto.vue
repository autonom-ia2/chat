<script setup>
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { larguraDaBarra } from '../../trazer/larguraDaBarra';

// #2894 — o fim. Enquanto a lista está sendo trazida: o andamento, com barra e
// a frase "pode fechar esta tela". Quando termina: "195 pessoas chegaram.", a
// ação principal (Ver as pessoas) e a discreta (Trazer outra lista).
defineProps({
  trazendo: { type: Boolean, default: false },
  porcentagem: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
  comErro: { type: Boolean, default: false },
});
const emit = defineEmits(['ver', 'outra', 'tentar']);

const { t } = useI18n();
</script>

<template>
  <section
    v-if="trazendo"
    data-relacionamentos="andamento"
    class="flex flex-col gap-6 p-8 border rounded-3xl border-n-weak bg-n-solid-1"
  >
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none tabular-nums md:text-4xl text-n-slate-12"
    >
      {{ t('RELACIONAMENTOS_TRAZER.ANDAMENTO.TITULO', { porcentagem }) }}
    </h1>
    <div
      role="progressbar"
      :aria-label="t('RELACIONAMENTOS_TRAZER.ANDAMENTO.ROTULO')"
      aria-valuemin="0"
      aria-valuemax="100"
      :aria-valuenow="porcentagem"
      class="h-3 overflow-hidden rounded-full bg-n-alpha-2"
    >
      <div
        class="h-full transition-all duration-500 ease-out rounded-full bg-n-blue-11 dark:bg-n-blue-9"
        :class="larguraDaBarra(porcentagem)"
      />
    </div>
    <p class="m-0 text-base text-n-slate-11">
      {{ t('RELACIONAMENTOS_TRAZER.ANDAMENTO.APOIO') }}
    </p>
    <div v-if="comErro" data-relacionamentos="erro">
      <ErroComTentarDeNovo
        :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.ANDAMENTO')"
        @tentar="emit('tentar')"
      />
    </div>
  </section>

  <HeroiEscuro v-else data-relacionamentos="pronto">
    <template #frase>
      <span
        role="heading"
        aria-level="1"
        data-titulo-da-tela
        tabindex="-1"
        class="outline-none tabular-nums"
      >
        {{
          t('RELACIONAMENTOS_TRAZER.PRONTO.CHEGARAM', { count: total }, total)
        }}
      </span>
    </template>
    <template #acao>
      <button
        type="button"
        data-relacionamentos="ver-as-pessoas"
        class="inline-flex items-center px-6 text-base font-semibold bg-white min-h-12 rounded-xl text-n-heroi hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-white"
        @click="emit('ver')"
      >
        {{ t('RELACIONAMENTOS_TRAZER.PRONTO.VER') }}
      </button>
    </template>
    <template #discreta>
      <button
        type="button"
        data-relacionamentos="trazer-outra"
        class="px-4 py-2 text-sm min-h-11 rounded-xl bg-white/10 text-white/90 ring-1 ring-inset ring-white/20 hover:bg-white/20 focus-visible:outline-2 focus-visible:outline-white"
        @click="emit('outra')"
      >
        {{ t('RELACIONAMENTOS_TRAZER.PRONTO.OUTRA') }}
      </button>
    </template>
  </HeroiEscuro>
</template>
