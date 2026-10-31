<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreSeloOrigem from './LivreSeloOrigem.vue';
import { fraseDoGatilho, fraseDoPasso } from '../prototipo/frases';

// #2414 F0 — uma automação na lista única: a frase (Quando → primeiro passo),
// a origem, o interruptor e a linha de fato da semana.
const props = defineProps({
  automacao: { type: Object, required: true },
  podeMudar: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir', 'alternar']);

const { t } = useI18n();

const receita = computed(() => props.automacao.versao?.receita);
const quando = computed(() => fraseDoGatilho(receita.value?.gatilho, t));
const primeiro = computed(() => {
  const passo = receita.value?.passos?.[0];
  return passo ? fraseDoPasso(passo, t) : '';
});
const outros = computed(() => (receita.value?.passos?.length || 1) - 1);

const fato = computed(() => {
  const { semana, pararam } = props.automacao.estatisticas;
  if (!semana) return t('AUTOMACAO_LIVRE.LISTA.FATO_NADA');
  const rodou = t('AUTOMACAO_LIVRE.LISTA.FATO_RODOU', { n: semana }, semana);
  if (!pararam) return rodou;
  return `${rodou} · ${t('AUTOMACAO_LIVRE.LISTA.FATO_PAROU', { n: pararam }, pararam)}`;
});
</script>

<template>
  <li
    data-linha
    class="flex flex-col gap-4 p-5 transition border shadow-sm sm:flex-row sm:items-center rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6"
  >
    <button
      type="button"
      data-abrir
      class="flex flex-col flex-1 min-w-0 gap-2 rounded-lg text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('abrir')"
    >
      <span class="flex flex-wrap items-center gap-2">
        <span class="text-lg font-semibold break-words text-n-slate-12">
          {{ automacao.nome }}
        </span>
        <LivreSeloOrigem :automacao="automacao" />
      </span>
      <span
        data-frase
        class="flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-11"
      >
        <span
          class="px-2.5 py-1 font-medium break-words rounded-lg bg-n-blue-2 text-n-blue-11"
        >
          {{ quando }}
        </span>
        <span
          class="i-lucide-arrow-right size-4 text-n-slate-9 rtl:rotate-180"
          aria-hidden="true"
        />
        <span
          class="px-2.5 py-1 font-medium break-words rounded-lg bg-n-teal-2 text-n-teal-11"
        >
          {{ primeiro }}
        </span>
        <span v-if="outros > 0" class="text-sm text-n-slate-10">
          {{ $t('AUTOMACAO_LIVRE.LISTA.MAIS_PASSOS', { n: outros }, outros) }}
        </span>
      </span>
      <span
        data-fato
        class="flex items-center gap-1.5 text-sm"
        :class="
          automacao.estatisticas.pararam ? 'text-n-amber-11' : 'text-n-slate-11'
        "
      >
        <span class="i-lucide-activity size-4" aria-hidden="true" />
        {{ fato }}
      </span>
    </button>
    <Button
      data-alterar
      :label="$t('AUTOMACAO_LIVRE.LISTA.ABRIR')"
      :aria-label="
        $t('AUTOMACAO_LIVRE.LISTA.ABRIR_ROTULO', { nome: automacao.nome })
      "
      icon="i-lucide-pencil"
      slate
      faded
      class="self-start min-h-11 sm:self-center shrink-0"
      @click="emit('abrir')"
    />
    <label
      class="flex items-center self-start gap-3 px-3 select-none sm:self-center min-h-11 shrink-0"
      :class="podeMudar ? 'cursor-pointer' : 'cursor-not-allowed opacity-60'"
    >
      <span
        class="text-sm font-semibold"
        :class="automacao.ativa ? 'text-n-teal-11' : 'text-n-slate-11'"
      >
        {{
          automacao.ativa
            ? $t('AUTOMACAO_LIVRE.LIGADA')
            : $t('AUTOMACAO_LIVRE.DESLIGADA')
        }}
      </span>
      <Switch
        data-interruptor
        class="mx-1.5 scale-[1.4]"
        :model-value="automacao.ativa"
        :disabled="!podeMudar"
        :aria-label="
          $t('AUTOMACAO_LIVRE.LISTA.INTERRUPTOR', { nome: automacao.nome })
        "
        @update:model-value="emit('alternar')"
      />
    </label>
  </li>
</template>
