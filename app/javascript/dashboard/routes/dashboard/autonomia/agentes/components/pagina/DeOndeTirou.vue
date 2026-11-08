<script setup>
import { useI18n } from 'vue-i18n';

// #1426 (t4d) — "De onde {agente} tirou", no cartão da resposta errada do autoteste: até 3 trechos do material que o
// agente usou para responder, com o arquivo e, no material grande, as páginas. Lista vazia: respondeu sem nenhum trecho
// do material, o que costuma explicar a resposta inventada. Vai dentro do <dl> do cartão (dt + dd).
defineProps({
  trechos: { type: Array, required: true },
  nome: { type: String, required: true },
});

const { t } = useI18n();

const onde = trecho =>
  trecho.paginas?.length === 2
    ? t('AGENTS.JORNADA.PAGINA.MATERIAL.AUTOTESTE.TIROU.ONDE_PAGINAS', {
        onde: trecho.onde,
        de: trecho.paginas[0],
        ate: trecho.paginas[1],
      })
    : trecho.onde;
</script>

<template>
  <dt class="font-semibold text-n-slate-11">
    {{
      t('AGENTS.JORNADA.PAGINA.MATERIAL.AUTOTESTE.TIROU.TITULO', {
        agente: nome,
      })
    }}
  </dt>
  <dd v-if="!trechos.length" data-sem-trecho class="m-0 text-n-slate-12">
    {{
      t('AGENTS.JORNADA.PAGINA.MATERIAL.AUTOTESTE.TIROU.NENHUM', {
        agente: nome,
      })
    }}
  </dd>
  <dd v-else class="m-0">
    <ul data-trechos class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="(trecho, indice) in trechos"
        :key="indice"
        class="flex flex-col gap-0.5 ps-3 border-s-2 border-n-weak"
      >
        <span data-onde class="text-xs font-semibold text-n-slate-11">
          {{ onde(trecho) }}
        </span>
        <q class="text-n-slate-12 line-clamp-3">{{ trecho.texto }}</q>
      </li>
    </ul>
  </dd>
</template>
