<script setup>
import { computed, ref, useId } from 'vue';
import { useSemFuncao } from '../useSemFuncao';

// O que muda para quem fica sem função (#2308, especificação 5.E e 9): aviso de bloco âmbar com "Vão passar a poder"
// e "Vão deixar de", calculado do contrato (diffEntre). "Mais detalhes" diz, sem jargão, que o acesso pelos canais e
// pelas colunas das vendas continua valendo.
const props = defineProps({
  ganha: { type: Array, default: () => [] },
  perde: { type: Array, default: () => [] },
  pessoas: { type: Number, default: 1 },
});

const { textoDa } = useSemFuncao();
const id = useId();
const detalhes = ref(false);

const titulo = computed(() => {
  if (props.ganha.length && props.perde.length) return 'GANHAR_E_PERDER';
  if (props.ganha.length) return 'SO_GANHAR';
  return props.perde.length ? 'SO_PERDER' : 'NADA';
});

const grupos = computed(() =>
  [
    {
      chave: 'PASSAM',
      ids: props.ganha,
      icone: 'i-lucide-check text-n-teal-11',
    },
    { chave: 'DEIXAM', ids: props.perde, icone: 'i-lucide-x text-n-ruby-11' },
  ].filter(grupo => grupo.ids.length)
);
</script>

<template>
  <div
    data-diff
    class="flex flex-col gap-3 p-4 rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
  >
    <p class="flex items-center gap-2 m-0 font-semibold text-n-slate-12">
      <span
        class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ $t(`FUNCOES_EQUIPE.DIFF.${titulo}`, pessoas) }}
    </p>
    <div
      v-for="grupo in grupos"
      :key="grupo.chave"
      :data-grupo="grupo.chave"
      class="flex flex-col gap-2"
    >
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ $t(`FUNCOES_EQUIPE.DIFF.${grupo.chave}`, pessoas) }}
      </p>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="item in grupo.ids"
          :key="item"
          :data-item="item"
          class="flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="size-5 shrink-0"
            :class="grupo.icone"
            aria-hidden="true"
          />
          {{ textoDa(item) }}
        </li>
      </ul>
    </div>
    <button
      type="button"
      data-mais-detalhes
      :aria-expanded="detalhes"
      :aria-controls="`${id}-detalhes`"
      class="self-start px-1 -mx-1 text-sm font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="detalhes = !detalhes"
    >
      {{ $t('FUNCOES_EQUIPE.DIFF.MAIS_DETALHES') }}
    </button>
    <p
      v-show="detalhes"
      :id="`${id}-detalhes`"
      data-nota-funil
      class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{ $t('FUNCOES_EQUIPE.SEM_FUNCAO.NOTA') }}
    </p>
  </div>
</template>
