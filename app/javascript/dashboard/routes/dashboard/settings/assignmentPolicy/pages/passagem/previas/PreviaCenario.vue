<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { CENARIO_FORA, CENARIO_ONLINE } from '../passagem';

// #1385 — o dia do exemplo, em duas opções lado a lado: sábado com a equipe fora, terça com a equipe online. Escolha
// única com <input type="radio"> de verdade (setas, Tab e leitor de tela vêm do navegador), alvo de 44 px e o mesmo
// desenho de escolhido das opções da tela (borda e fundo azuis).
const cenario = defineModel({ type: String, required: true });

const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';
const nome = useId();
const OPCOES = [
  { valor: CENARIO_FORA, chave: 'CENARIO_FORA', icone: 'i-lucide-moon' },
  { valor: CENARIO_ONLINE, chave: 'CENARIO_ONLINE', icone: 'i-lucide-sun' },
];
</script>

<template>
  <div
    role="radiogroup"
    :aria-label="t(`${P}.CENARIO_ROTULO`)"
    data-previa-cenario
    class="grid grid-cols-2 gap-1 rounded-xl bg-n-alpha-2 p-1"
  >
    <label
      v-for="opcao in OPCOES"
      :key="opcao.valor"
      class="flex min-h-11 cursor-pointer items-center justify-center gap-2 rounded-lg px-2 text-center text-sm font-medium transition-colors has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
      :class="
        cenario === opcao.valor
          ? 'bg-n-solid-1 text-n-blue-11 shadow-sm ring-1 ring-n-blue-8'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      <input
        v-model="cenario"
        type="radio"
        class="sr-only"
        :name="nome"
        :value="opcao.valor"
      />
      <span
        class="size-4 shrink-0 max-sm:hidden"
        :class="opcao.icone"
        aria-hidden="true"
      />
      {{ t(`${P}.${opcao.chave}`) }}
    </label>
  </div>
</template>
