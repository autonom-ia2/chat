<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CelularConversa from './CelularConversa.vue';

// #3219 — um papel no passo 1 de "Criar agente" ("O que o seu agente vai fazer?").
// `destaque`: atender clientes, o caminho da maioria — maior, com ícone azul e o "Escolher" azul. O "Escolher" é o
// botão e se estica sobre o cartão (after:absolute), como o "Usar este" do ModeloCartao; o hover troca a cor, nunca
// usa filtro (filter prende o after ao botão e o resto do cartão deixa de responder ao clique). `exemplo` (tela inicial):
// um par de balões no celular de exemplo, à direita do texto no computador e embaixo dele no celular.
// Os outros são cartões baixos, e o cartão inteiro é o botão. `comNome`: embaixo do título, uma etiqueta com o nome com
// que o agente aparece na lista (o título diz a tarefa). Quem só vê recebe o cartão sem ação.
const props = defineProps({
  papel: { type: Object, required: true },
  destaque: { type: Boolean, default: false },
  podeUsar: { type: Boolean, default: false },
  exemplo: { type: Array, default: () => [] },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();
const tituloId = `papel-${useId()}`;
const base = computed(
  () => `AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEIS.${props.papel.i18n}`
);
const titulo = computed(() => t(`${base.value}.TITULO`));
const comExemplo = computed(() => props.exemplo.length > 0);
const escolher = () => {
  if (props.podeUsar) emit('escolher', props.papel.chave);
};
</script>

<template>
  <li
    v-if="destaque"
    :data-papel="papel.chave"
    class="relative grid gap-5 p-6 transition shadow-sm md:p-8 rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    :class="[
      comExemplo
        ? 'md:grid-cols-[minmax(0,1fr)_17rem] md:gap-x-10 md:items-center'
        : 'md:grid-cols-[minmax(0,1fr)_auto] md:items-center',
      podeUsar ? 'hover:ring-n-blue-11 hover:shadow-md' : '',
    ]"
  >
    <div
      class="flex items-start min-w-0 gap-4"
      :class="comExemplo ? 'md:self-end' : ''"
    >
      <span
        aria-hidden="true"
        class="grid size-12 md:size-14 rounded-2xl place-items-center shrink-0 bg-n-blue-3 text-n-blue-11"
      >
        <span class="size-6 md:size-7" :class="papel.icone" />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <h2
          :id="tituloId"
          class="m-0 text-xl font-semibold leading-snug md:text-2xl text-n-slate-12"
        >
          {{ titulo }}
        </h2>
        <p class="m-0 text-base leading-relaxed text-n-slate-11">
          {{ t(`${base}.TEXTO`) }}
        </p>
      </div>
    </div>
    <CelularConversa
      v-if="comExemplo"
      tamanho="mini"
      class="md:col-start-2 md:row-start-1 md:row-span-2"
      :mensagens="exemplo"
      :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
      :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
    />
    <button
      v-if="podeUsar"
      type="button"
      data-escolher-papel
      :aria-label="
        t('AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEL.ESCOLHER_ARIA', { titulo })
      "
      class="inline-flex items-center justify-center w-full gap-2 px-6 text-base font-semibold text-white md:w-auto min-h-12 rounded-xl bg-n-blue-11 dark:text-n-slate-1 hover:bg-n-blue-10 after:absolute after:inset-0 after:rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      :class="
        comExemplo
          ? 'md:col-start-1 md:row-start-2 md:self-start md:justify-self-start md:ms-[4.5rem]'
          : ''
      "
      @click="escolher"
    >
      {{ t('AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEL.ESCOLHER') }}
      <span
        class="i-lucide-arrow-right size-5 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
  </li>
  <li v-else class="flex">
    <component
      :is="podeUsar ? 'button' : 'div'"
      :type="podeUsar ? 'button' : undefined"
      :data-papel="papel.chave"
      class="flex items-start w-full gap-3 p-4 transition shadow-sm text-start rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      :class="podeUsar ? 'hover:ring-n-blue-11 hover:shadow-md' : ''"
      @click="escolher"
    >
      <span
        aria-hidden="true"
        class="grid size-10 rounded-xl place-items-center shrink-0 bg-n-alpha-2 text-n-slate-11"
      >
        <span class="size-5" :class="papel.icone" />
      </span>
      <span class="flex flex-col items-start min-w-0 gap-1 grow">
        <span class="text-base font-semibold leading-snug text-n-slate-12">
          {{ titulo }}
        </span>
        <span
          v-if="papel.comNome"
          data-nome-na-lista
          class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-alpha-2 text-n-slate-11"
        >
          {{ t(`${base}.NOME`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t(`${base}.TEXTO`) }}
        </span>
      </span>
      <span
        v-if="podeUsar"
        aria-hidden="true"
        class="self-center i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
      />
    </component>
  </li>
</template>
