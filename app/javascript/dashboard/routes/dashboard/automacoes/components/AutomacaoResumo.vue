<script setup>
// #859 — a automação em três blocos: Quando → Se → Então. O texto vem pronto de
// `descreverAutomacao` (helper/automacaoEmPortugues.js); sem automação ainda, a
// caixa explica onde o resumo vai aparecer.
defineProps({
  descricao: { type: Object, default: null },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    :aria-label="$t('AUTOMACOES.RESUMO.TITULO')"
  >
    <h2 class="text-base font-medium text-n-slate-12">
      {{ $t('AUTOMACOES.RESUMO.TITULO') }}
    </h2>
    <p v-if="!descricao" data-resumo-vazio class="text-sm text-n-slate-11">
      {{ $t('AUTOMACOES.RESUMO.VAZIO') }}
    </p>
    <ol v-else class="flex flex-col gap-3">
      <li class="flex flex-col gap-1">
        <span class="text-xs font-medium uppercase text-n-slate-11">
          {{ $t('AUTOMACOES.RESUMO.QUANDO') }}
        </span>
        <span data-quando class="text-sm text-n-slate-12">
          {{ descricao.quando }}
        </span>
      </li>
      <li class="flex flex-col gap-1">
        <span class="text-xs font-medium uppercase text-n-slate-11">
          {{ $t('AUTOMACOES.RESUMO.SE') }}
        </span>
        <ul v-if="descricao.se.length" data-se class="flex flex-col gap-1">
          <li
            v-for="(condicao, indice) in descricao.se"
            :key="indice"
            class="text-sm text-n-slate-12"
          >
            <span v-if="indice > 0" class="text-n-slate-11">
              {{ descricao.se[indice - 1].liga }}
            </span>
            {{ condicao.texto }}
          </li>
        </ul>
        <span v-else class="text-sm text-n-slate-12">
          {{ $t('AUTOMACOES.RESUMO.SEM_CONDICAO') }}
        </span>
      </li>
      <li class="flex flex-col gap-1">
        <span class="text-xs font-medium uppercase text-n-slate-11">
          {{ $t('AUTOMACOES.RESUMO.ENTAO') }}
        </span>
        <ul data-entao class="flex flex-col gap-1">
          <li
            v-for="(acao, indice) in descricao.entao"
            :key="indice"
            class="text-sm text-n-slate-12"
          >
            {{ acao }}
          </li>
        </ul>
      </li>
    </ol>
  </section>
</template>
