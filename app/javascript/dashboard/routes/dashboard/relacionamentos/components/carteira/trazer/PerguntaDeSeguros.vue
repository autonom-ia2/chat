<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { SO_PESSOAS, TEM_SEGUROS } from '../../../carteira/segurosDaPlanilha';

// #2897 — "Esta planilha tem seguros?": a pergunta que só a conta com a
// carteira de seguros recebe. Uma ação só: a resposta já segue para a próxima
// tela (quem grava é a tela das listas, junto das outras respostas).
// `resposta`: o que a pessoa respondeu antes (ela voltou a esta pergunta).
// `recusa` (`{ chave }`): a resposta que não foi salva fica dita aqui, como
// alerta, com o foco de volta nas respostas. `relendo`: a planilha está sendo
// lida de novo. Com a resposta sendo gravada, os botões esperam.
const props = defineProps({
  resposta: { type: String, default: '' },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['responder', 'voltar']);

const { t } = useI18n();
const id = useId();
const raiz = ref(null);

const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.PERGUNTA';
const opcoes = computed(() => [
  { valor: TEM_SEGUROS, rotulo: t(`${BASE}.TEM_SEGUROS`) },
  { valor: SO_PESSOAS, rotulo: t(`${BASE}.SO_PESSOAS`) },
]);

// A recusa chegou: o foco volta à primeira resposta, quando ela religar.
let devoOFoco = false;
const focarQuandoDer = async () => {
  if (!devoOFoco || props.ocupado) return;
  devoOFoco = false;
  await nextTick();
  raiz.value?.querySelector('[data-carteira="resposta-dos-seguros"]')?.focus();
};
watch(
  () => props.recusa,
  recusa => {
    devoOFoco = Boolean(recusa);
    focarQuandoDer();
  }
);
watch(() => props.ocupado, focarQuandoDer);
</script>

<template>
  <section
    ref="raiz"
    data-carteira="pergunta-de-seguros"
    class="flex flex-col gap-8"
  >
    <div class="flex flex-col gap-3">
      <h1
        :id="`${id}-titulo`"
        data-titulo-da-tela
        tabindex="-1"
        :aria-describedby="`${id}-apoio`"
        class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
      >
        {{ t(`${BASE}.TITULO`) }}
      </h1>
      <p :id="`${id}-apoio`" class="m-0 text-lg text-n-slate-11">
        {{ t(`${BASE}.APOIO`) }}
      </p>
    </div>
    <div
      role="group"
      :aria-labelledby="`${id}-titulo`"
      class="grid gap-3 sm:grid-cols-2"
    >
      <button
        v-for="opcao in opcoes"
        :key="opcao.valor"
        type="button"
        data-carteira="resposta-dos-seguros"
        :data-resposta="opcao.valor"
        :aria-describedby="recusa ? `${id}-erro` : undefined"
        class="flex items-center justify-between gap-3 px-5 py-4 text-lg font-semibold transition-colors text-start min-h-16 rounded-2xl text-n-slate-12 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          resposta === opcao.valor
            ? 'bg-n-blue-3 ring-2 ring-inset ring-n-blue-9'
            : 'bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:enabled:bg-n-alpha-1'
        "
        :disabled="ocupado"
        @click="emit('responder', opcao.valor)"
      >
        <span>
          {{ opcao.rotulo }}
          <span v-if="resposta === opcao.valor" class="sr-only">
            {{ t(`${BASE}.JA_RESPONDIDA`) }}
          </span>
        </span>
        <span
          class="size-5 shrink-0"
          :class="
            resposta === opcao.valor
              ? 'i-lucide-check text-n-blue-11'
              : 'i-lucide-arrow-right text-n-slate-10 rtl:rotate-180'
          "
          aria-hidden="true"
        />
      </button>
    </div>
    <p
      v-if="recusa"
      :id="`${id}-erro`"
      data-carteira="erro-da-pergunta"
      role="alert"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ t(recusa.chave) }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        slate
        faded
        size="lg"
        data-carteira="voltar"
        :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
        :disabled="ocupado"
        @click="emit('voltar')"
      />
      <p
        data-carteira="relendo"
        role="status"
        class="m-0 text-base text-n-slate-11"
      >
        {{ relendo ? t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') : '' }}
      </p>
    </div>
  </section>
</template>
