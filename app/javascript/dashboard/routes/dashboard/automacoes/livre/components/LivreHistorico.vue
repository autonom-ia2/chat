<script setup>
import { useI18n } from 'vue-i18n';
import { quando, quandoFoi } from '../prototipo/frases';

// #2414 F0 — "O que aconteceu": uma linha por passo, em frase, com o motivo
// quando pulou, parou ou falhou. Guardado por 30 dias.
defineProps({
  registros: { type: Array, default: () => [] },
  // No painel do cartão o nome do cartão não se repete em cada linha.
  semAlvo: { type: Boolean, default: false },
});

const { t, locale } = useI18n();

const VISUAL = {
  feito: { icone: 'i-lucide-check', tom: 'bg-n-teal-3 text-n-teal-11' },
  esperando: { icone: 'i-lucide-clock', tom: 'bg-n-blue-3 text-n-blue-11' },
  pulou: {
    icone: 'i-lucide-skip-forward',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  parou: { icone: 'i-lucide-octagon-x', tom: 'bg-n-slate-3 text-n-slate-11' },
  falhou: {
    icone: 'i-lucide-triangle-alert',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
  },
};

const frase = registro => {
  const params = { ...registro.params };
  if (params.ate) params.ate = quando(params.ate, locale?.value);
  return t(
    `AUTOMACAO_LIVRE.REGISTROS.${registro.chave}`,
    params,
    params.dias || 1
  );
};
</script>

<template>
  <p
    v-if="!registros.length"
    data-historico-vazio
    class="mb-0 text-[0.9375rem] text-n-slate-11"
  >
    {{ $t('AUTOMACAO_LIVRE.HISTORICO.VAZIO') }}
  </p>
  <ul
    v-else
    data-historico
    class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
  >
    <li
      v-for="registro in registros"
      :key="registro.id"
      class="flex items-start gap-3 py-3"
    >
      <span
        class="grid rounded-full place-items-center size-8 shrink-0"
        :class="VISUAL[registro.resultado].tom"
      >
        <span
          class="size-4"
          :class="VISUAL[registro.resultado].icone"
          aria-hidden="true"
        />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="text-[0.9375rem] text-n-slate-12 break-words">
          {{
            !semAlvo && registro.alvo
              ? $t('AUTOMACAO_LIVRE.HISTORICO.LINHA', {
                  alvo: registro.alvo,
                  frase: frase(registro),
                })
              : frase(registro)
          }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ quandoFoi(registro.em, locale) }}
        </span>
      </span>
    </li>
  </ul>
</template>
