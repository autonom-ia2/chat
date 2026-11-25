<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #3219 — um jeito de começar no passo 2 ("Conversar com a IA", "Escrever eu mesmo" ou, com ramos, um modelo geral).
// `linha`: em atender clientes, embaixo dos prontos, compacta sobre o navy (ícone, título, frase e seta).
// `cartao`: nos outros papéis, cartão branco do mesmo tamanho do vizinho; o "Começar" se estica sobre o cartão
// (after:absolute), como o "Usar este" do ModeloCartao, e continua um botão só. `principal`: o jeito recomendado, com
// o botão azul cheio e o selo "Mais fácil".
// `opcao.base`: a chave i18n do título e da frase (os modelos usam a deles, AGENTS.JORNADA.MODELOS.<I18N>); sem ela,
// CRIAR_EM_PASSOS.COMO.<I18N>.
const props = defineProps({
  opcao: { type: Object, required: true },
  variante: {
    type: String,
    default: 'cartao',
    validator: valor => ['cartao', 'linha'].includes(valor),
  },
  principal: { type: Boolean, default: false },
  podeUsar: { type: Boolean, default: false },
  comecando: { type: Boolean, default: false },
  bloqueado: { type: Boolean, default: false },
});

const emit = defineEmits(['usar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO';
const base = computed(() => props.opcao.base || `${NS}.${props.opcao.i18n}`);
const titulo = computed(() => t(`${base.value}.TITULO`));
const usar = () => {
  if (!props.podeUsar || props.comecando || props.bloqueado) return;
  emit('usar', props.opcao.chave);
};
</script>

<template>
  <li v-if="variante === 'linha'" class="flex">
    <button
      type="button"
      :data-opcao="opcao.chave"
      :disabled="!podeUsar || bloqueado"
      :aria-busy="comecando ? 'true' : undefined"
      class="flex items-start w-full gap-3 p-4 text-white transition text-start rounded-2xl bg-white/10 ring-1 ring-inset ring-white/20 hover:bg-white/15 min-h-11 disabled:opacity-60 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      @click="usar"
    >
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-10 shrink-0 bg-white/10"
      >
        <span class="size-5" :class="opcao.icone" />
      </span>
      <span class="flex flex-col gap-0.5 grow min-w-0">
        <span class="text-base font-semibold">
          {{ comecando ? t('AGENTS.JORNADA.COMUM.COMECANDO') : titulo }}
        </span>
        <span class="text-sm text-white/80">{{ t(`${base}.TEXTO`) }}</span>
      </span>
      <span
        aria-hidden="true"
        class="self-center i-lucide-chevron-right size-5 shrink-0 text-white/70 rtl:rotate-180"
      />
    </button>
  </li>
  <li
    v-else
    :data-opcao="opcao.chave"
    class="relative flex flex-col gap-4 p-6 transition shadow-sm rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    :class="[
      podeUsar && !bloqueado ? 'hover:ring-n-blue-11 hover:shadow-md' : '',
      bloqueado ? 'opacity-60' : '',
    ]"
  >
    <div class="flex items-start justify-between gap-3">
      <span
        aria-hidden="true"
        class="grid size-12 rounded-xl place-items-center shrink-0 bg-n-blue-3 text-n-blue-11"
      >
        <span class="size-6" :class="opcao.icone" />
      </span>
      <span
        v-if="principal"
        data-mais-facil
        class="px-2.5 py-1 text-xs font-bold rounded-full bg-n-teal-3 text-n-teal-11"
      >
        {{ t(`${NS}.MAIS_FACIL`) }}
      </span>
    </div>
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-xl font-semibold leading-snug text-n-slate-12">
        {{ titulo }}
      </h2>
      <p class="m-0 text-base leading-relaxed text-n-slate-11">
        {{ t(`${base}.TEXTO`) }}
      </p>
    </div>
    <button
      v-if="podeUsar"
      type="button"
      data-usar-opcao
      :disabled="bloqueado"
      :aria-busy="comecando ? 'true' : undefined"
      :aria-label="t(`${NS}.COMECAR_ARIA`, { titulo })"
      class="inline-flex items-center justify-center w-full gap-2 px-5 mt-auto text-base font-semibold transition min-h-12 rounded-xl after:absolute after:inset-0 after:rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed"
      :class="
        principal
          ? 'bg-n-blue-11 text-white dark:text-n-slate-1 hover:bg-n-blue-10'
          : 'bg-n-solid-1 text-n-blue-11 ring-1 ring-inset ring-n-blue-9 hover:bg-n-blue-2'
      "
      @click="usar"
    >
      {{ comecando ? t('AGENTS.JORNADA.COMUM.COMECANDO') : t(`${NS}.COMECAR`) }}
    </button>
  </li>
</template>
