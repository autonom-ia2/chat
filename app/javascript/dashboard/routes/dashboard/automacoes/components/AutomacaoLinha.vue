<script setup>
import { computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #982 — uma automação na lista, lida como frase: Quando [evento] → [o que faz].
// O cartão abre a automação; "Alterar" diz isso com todas as letras (o cartão
// clicável sozinho não se anunciava); o interruptor liga e desliga ali mesmo.
const props = defineProps({
  automacao: { type: Object, required: true },
  descricao: { type: Object, required: true },
  criadaPeloGuia: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  mudando: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir', 'alternar']);

// O ícone diz de relance de que tipo é a automação.
const VISUAL_DO_EVENTO = {
  conversation_resolved: {
    icone: 'i-lucide-circle-check-big',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  conversation_created: {
    icone: 'i-lucide-message-circle-heart',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  message_created: {
    icone: 'i-lucide-message-square-text',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  conversation_opened: {
    icone: 'i-lucide-rotate-ccw',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
};
const VISUAL_PADRAO = {
  icone: 'i-lucide-zap',
  tom: 'bg-n-slate-3 text-n-slate-11',
};

const visual = computed(
  () => VISUAL_DO_EVENTO[props.automacao.event_name] || VISUAL_PADRAO
);
const primeiraAcao = computed(() => props.descricao.entao[0] || '');
const outrasAcoes = computed(() => props.descricao.entao.length - 1);
</script>

<template>
  <li
    class="flex flex-col gap-4 p-5 transition border shadow-sm sm:flex-row sm:items-center rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6"
    :class="automacao.active ? '' : 'bg-n-solid-1/70'"
  >
    <span
      class="hidden sm:grid place-items-center size-[3.25rem] shrink-0 rounded-2xl"
      :class="visual.tom"
    >
      <span class="size-6" :class="visual.icone" aria-hidden="true" />
    </span>
    <button
      type="button"
      data-abrir
      class="flex flex-col flex-1 min-w-0 gap-2 text-start rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :title="$t('AUTOMACOES.LISTA.ABRIR', { nome: automacao.name })"
      @click="emit('abrir')"
    >
      <span class="flex flex-wrap items-center gap-2">
        <span class="text-lg font-semibold break-words text-n-slate-12">
          {{ automacao.name }}
        </span>
        <span
          v-if="criadaPeloGuia"
          data-selo-guia
          class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-sparkles size-3" aria-hidden="true" />
          {{ $t('AUTOMACOES.LISTA.SELO_GUIA') }}
        </span>
      </span>
      <span
        data-frase
        class="flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-11"
      >
        <span
          class="px-2.5 py-1 font-medium rounded-lg bg-n-blue-2 text-n-blue-11 break-words"
        >
          {{ descricao.quando }}
        </span>
        <span
          class="i-lucide-arrow-right size-4 text-n-slate-9 rtl:rotate-180"
          aria-hidden="true"
        />
        <span
          class="px-2.5 py-1 font-medium rounded-lg bg-n-teal-2 text-n-teal-11 break-words"
        >
          {{ primeiraAcao }}
        </span>
        <span v-if="outrasAcoes > 0" class="text-sm text-n-slate-10">
          {{ $t('AUTOMACOES.LISTA.MAIS_ACOES', { n: outrasAcoes }) }}
        </span>
      </span>
    </button>
    <Button
      data-alterar
      :label="$t('AUTOMACOES.LISTA.ALTERAR')"
      :aria-label="$t('AUTOMACOES.LISTA.ABRIR', { nome: automacao.name })"
      icon="i-lucide-pencil"
      slate
      faded
      class="self-start min-h-11 sm:self-center shrink-0"
      @click="emit('abrir')"
    />
    <label
      class="flex items-center self-start gap-3 px-3 select-none sm:self-center min-h-11 shrink-0"
      :class="
        podeMudar && !mudando
          ? 'cursor-pointer'
          : 'cursor-not-allowed opacity-60'
      "
    >
      <span
        class="text-sm font-semibold"
        :class="automacao.active ? 'text-n-teal-11' : 'text-n-slate-11'"
      >
        {{
          automacao.active
            ? $t('AUTOMACOES.LISTA.LIGADA')
            : $t('AUTOMACOES.LISTA.DESLIGADA')
        }}
      </span>
      <Switch
        data-interruptor
        class="mx-1.5 scale-[1.4]"
        :model-value="automacao.active"
        :disabled="!podeMudar || mudando"
        :aria-label="
          $t('AUTOMACOES.LISTA.INTERRUPTOR', { nome: automacao.name })
        "
        @update:model-value="emit('alternar')"
      />
    </label>
  </li>
</template>
