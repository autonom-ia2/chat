<script setup>
import { computed } from 'vue';

// #1384 — o Kanban em miniatura, só de leitura. Sai do mesmo estado do
// formulário: muda enquanto a pessoa preenche. A coluna em edição acende e a
// conversa nova aparece onde vai cair. Os cartões copiam o CrmKanbanCard
// (faixa da cor à esquerda, cantos de 1.25rem). Cada coluna tem largura
// mínima: o nome cabe em até duas linhas, sem hífen. No celular o quadro vira
// uma lista de colunas, para todas caberem; com mais de cinco, também.
const props = defineProps({
  nome: { type: String, default: '' },
  // [{ chave, nome, cor, total (número ou null), falta (sem frase) }]
  etapas: { type: Array, required: true },
  acesa: { type: Number, default: -1 },
  chegando: { type: Number, default: -1 },
  exemplo: { type: String, default: '' },
});

const MAX_CARTOES = 3;
// Até cinco colunas cabem lado a lado na prévia; com mais, vira lista.
const MAX_LADO_A_LADO = 5;
const emLista = computed(() => props.etapas.length > MAX_LADO_A_LADO);

const colunas = computed(() =>
  props.etapas.map((etapa, indice) => {
    const temTotal = Number.isFinite(etapa.total);
    const vagas = temTotal ? Math.min(etapa.total, MAX_CARTOES) : 2;
    const chega = indice === props.chegando;
    return {
      ...etapa,
      numero: indice + 1,
      acesa: indice === props.acesa,
      chega,
      temTotal,
      vazios: Math.max(vagas - (chega ? 1 : 0), 0),
    };
  })
);
</script>

<template>
  <section
    data-funil-quadro
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-2.5 shadow-sm"
    :aria-label="$t('CRM_FUNIL.PREVIA.QUADRO', { nome })"
  >
    <header class="flex items-center gap-2 px-1">
      <span class="i-lucide-kanban size-4 text-n-slate-11" aria-hidden="true" />
      <span
        class="min-w-0 flex-1 truncate text-sm font-semibold text-n-slate-12"
      >
        {{ nome || $t('CRM_FUNIL.PREVIA.SEM_NOME') }}
      </span>
      <span class="shrink-0 text-xs text-n-slate-11">
        {{
          $t('CRM_FUNIL.PREVIA.COLUNAS', { n: etapas.length }, etapas.length)
        }}
      </span>
    </header>
    <!-- No celular as colunas viram uma lista: as cinco aparecem inteiras,
         sem rolar para o lado. -->
    <ol
      data-funil-quadro-lista
      class="m-0 flex list-none flex-col gap-1 p-0"
      :class="{ 'sm:hidden': !emLista }"
    >
      <li
        v-for="coluna in colunas"
        :key="coluna.chave"
        :aria-current="coluna.acesa ? 'true' : undefined"
        class="flex min-h-10 items-center gap-2 rounded-xl px-2 py-1.5"
        :class="
          coluna.acesa
            ? 'bg-n-blue-2 ring-2 ring-inset ring-n-blue-8'
            : 'bg-n-alpha-2'
        "
      >
        <span
          class="grid size-5 shrink-0 place-items-center rounded-full text-xs font-bold"
          :class="
            coluna.acesa
              ? 'bg-n-blue-9 text-white'
              : 'bg-n-solid-1 text-n-slate-11'
          "
        >
          {{ coluna.numero }}
        </span>
        <span
          class="h-4 w-1 shrink-0 rounded-full"
          :style="{ backgroundColor: coluna.cor }"
          aria-hidden="true"
        />
        <span
          class="min-w-0 flex-1 truncate text-sm font-semibold text-n-slate-12"
        >
          {{ coluna.nome }}
        </span>
        <span
          v-if="coluna.chega"
          class="inline-flex shrink-0 items-center gap-1 rounded-full border border-n-teal-8 bg-n-solid-1 px-2 py-0.5 text-xs font-semibold text-n-slate-12"
        >
          <span class="size-2.5 rounded-full bg-n-blue-5" aria-hidden="true" />
          {{ exemplo }}
        </span>
        <span
          v-if="coluna.falta"
          class="shrink-0 rounded-lg border border-dashed border-n-amber-8 bg-n-amber-2 px-1.5 py-0.5 text-xs text-n-amber-11"
        >
          {{ $t('CRM_FUNIL.PREVIA.FALTA') }}
        </span>
        <span
          v-else-if="coluna.temTotal"
          class="shrink-0 text-xs text-n-slate-11"
        >
          {{
            $t('CRM_FUNIL.PREVIA.CLIENTES', { n: coluna.total }, coluna.total)
          }}
        </span>
      </li>
    </ol>
    <ol
      class="m-0 hidden list-none auto-cols-[minmax(5.25rem,1fr)] grid-flow-col gap-1 overflow-x-auto p-0 pb-1"
      :class="{ 'sm:grid': !emLista }"
    >
      <li
        v-for="coluna in colunas"
        :key="coluna.chave"
        :data-coluna="coluna.nome"
        :aria-current="coluna.acesa ? 'true' : undefined"
        class="flex min-w-0 flex-col gap-1.5 rounded-xl p-1 transition"
        :class="
          coluna.acesa
            ? 'bg-n-blue-2 ring-2 ring-inset ring-n-blue-8'
            : 'bg-n-alpha-2'
        "
      >
        <span class="flex items-center gap-1">
          <span
            class="grid size-5 shrink-0 place-items-center rounded-full text-xs font-bold"
            :class="
              coluna.acesa
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-solid-1 text-n-slate-11'
            "
          >
            {{ coluna.numero }}
          </span>
          <span
            class="h-1 min-w-0 flex-1 rounded-full"
            :style="{ backgroundColor: coluna.cor }"
            aria-hidden="true"
          />
        </span>
        <span
          :title="coluna.nome"
          class="line-clamp-2 min-h-8 hyphens-none break-words px-0.5 text-xs font-semibold leading-4 text-n-slate-12"
        >
          {{ coluna.nome }}
        </span>
        <span v-if="coluna.temTotal" class="-mt-1 text-xs text-n-slate-11">
          {{
            $t('CRM_FUNIL.PREVIA.CLIENTES', { n: coluna.total }, coluna.total)
          }}
        </span>
        <span
          v-if="coluna.chega"
          data-chegando
          class="relative overflow-hidden rounded-[1.25rem] border border-n-teal-8 bg-n-solid-1 py-2 pe-1.5 ps-2.5 shadow-md"
        >
          <span
            class="absolute inset-y-0 start-0 w-[0.188rem]"
            :style="{ backgroundColor: coluna.cor }"
            aria-hidden="true"
          />
          <span class="flex items-center gap-1">
            <span
              class="size-3.5 shrink-0 rounded-full bg-n-blue-5"
              aria-hidden="true"
            />
            <span class="truncate text-xs font-semibold text-n-slate-12">
              {{ exemplo }}
            </span>
          </span>
          <span
            class="mt-1.5 block h-1 w-3/4 rounded-full bg-n-slate-4"
            aria-hidden="true"
          />
        </span>
        <span
          v-for="vazio in coluna.vazios"
          :key="vazio"
          aria-hidden="true"
          class="relative block h-9 overflow-hidden rounded-[1.25rem] border border-n-weak bg-n-solid-1"
        >
          <span
            class="absolute inset-y-0 start-0 w-[0.188rem] opacity-60"
            :style="{ backgroundColor: coluna.cor }"
          />
          <span
            class="ms-2.5 mt-2.5 block h-1 w-1/2 rounded-full bg-n-slate-4"
          />
          <span
            class="ms-2.5 mt-1.5 block h-1 w-1/3 rounded-full bg-n-slate-3"
          />
        </span>
        <span
          v-if="coluna.falta"
          class="rounded-lg border border-dashed border-n-amber-8 bg-n-amber-2 px-1 py-1 text-xs leading-4 text-n-amber-11"
        >
          {{ $t('CRM_FUNIL.PREVIA.FALTA') }}
        </span>
      </li>
    </ol>
  </section>
</template>
