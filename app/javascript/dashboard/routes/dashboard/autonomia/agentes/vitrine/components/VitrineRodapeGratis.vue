<script setup>
import { useI18n } from 'vue-i18n';

// #2858 — o rodapé dos cartões grátis, no mesmo desenho do rodapé Premium (`VitrinePreco`): o divisor, a barrinha
// tracejada e duas linhas. Assim os cartões de uma linha da grade ficam do mesmo tamanho e com os rodapés alinhados.
// Em verde-água, não no índigo do Premium: aqui a barrinha é só enfeite, não conta nada. "Não entra na fatura" vale
// para todas as grátis (todas têm limite por dia, por isso nada de "sem limite"). Fica dentro do botão do cartão, por
// isso só `span`.

// Mesmo número de marcas da barrinha Premium (as 20 grátis do mês), para os dois rodapés terem o mesmo desenho.
const MARCAS = 20;

const NS = 'AGENTS.VITRINE.CARTAO.GRATIS';
const { t } = useI18n();
</script>

<template>
  <span
    class="flex flex-col gap-2 pt-3 border-t border-n-weak"
    data-vitrine-gratis
  >
    <span class="flex gap-0.5" aria-hidden="true">
      <span
        v-for="marca in MARCAS"
        :key="marca"
        class="flex-1 h-1.5 rounded-full bg-n-teal-6"
      />
    </span>
    <span class="flex flex-col gap-0.5">
      <span class="text-sm font-semibold text-n-teal-11">
        {{ t(`${NS}.TITULO`) }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ t(`${NS}.TEXTO`) }}
      </span>
    </span>
  </span>
</template>
