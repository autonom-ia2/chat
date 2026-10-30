<script setup>
import { computed } from 'vue';
// Seus posts (#2302): um número, no mesmo quadro do detalhe de anúncio (MetaAdsAdDetail): o nome em cima, o número
// embaixo e, só no perfil, a comparação com o período anterior e uma nota. O quadro é uma subgrade da grade de
// fora (grid-rows-subgrid): nome, número, comparação e nota caem nas mesmas linhas em todos os quadros da fileira,
// mesmo quando um nome quebra em duas linhas ou um quadro não tem nota. O lado do anúncio é uma marca no nome; a
// frase que explica a marca fica uma vez, acima da grade.
const props = defineProps({
  label: { type: String, required: true },
  valor: { type: String, required: true },
  // { texto, tom: 'sobe' | 'desce' | 'igual' } ou null.
  mudanca: { type: Object, default: null },
  extra: { type: String, default: '' },
  // true quando o número pode incluir anúncio (a marca do megafone).
  anuncio: { type: Boolean, default: false },
  // Se algum quadro da fileira tem comparação ou nota: a linha existe para todos (vazia onde não houver), para a
  // nota de um quadro não subir para a linha da comparação do vizinho. Sem nenhum, a linha nem existe.
  temMudanca: { type: Boolean, default: false },
  temNota: { type: Boolean, default: false },
});
const SPAN = { 2: 'row-span-2', 3: 'row-span-3', 4: 'row-span-4' };
const linhas = computed(
  () => 2 + Number(props.temMudanca) + Number(props.temNota)
);

const TONS = {
  sobe: { icon: 'i-lucide-arrow-up-right', class: 'text-n-teal-11' },
  desce: { icon: 'i-lucide-arrow-down-right', class: 'text-n-ruby-11' },
  igual: { icon: 'i-lucide-equal', class: 'text-n-slate-11' },
};
</script>

<template>
  <div
    class="grid min-w-0 grid-rows-subgrid gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak"
    :class="SPAN[linhas]"
  >
    <dt class="text-sm text-n-slate-11">
      {{ label }}
      <span
        v-if="anuncio"
        data-seus-posts-marca-anuncio
        class="i-lucide-megaphone ms-0.5 inline-block size-3.5 align-[-2px] text-n-slate-10"
        :title="$t('SEUS_POSTS.TILES.MAYBE_ADS')"
      />
      <span v-if="anuncio" class="sr-only">
        {{ $t('SEUS_POSTS.TILES.MAYBE_ADS') }}
      </span>
    </dt>
    <dd
      class="m-0 self-end truncate text-xl font-semibold tabular-nums text-n-slate-12 sm:text-2xl"
    >
      {{ valor }}
    </dd>
    <dd
      v-if="mudanca || temMudanca"
      class="m-0 flex items-start gap-1 text-xs font-medium sm:text-sm"
      :class="mudanca && TONS[mudanca.tom].class"
    >
      <template v-if="mudanca">
        <span
          :class="TONS[mudanca.tom].icon"
          class="mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ mudanca.texto }}
      </template>
    </dd>
    <dd v-if="extra || temNota" class="m-0 text-xs text-n-slate-11">
      {{ extra }}
    </dd>
  </div>
</template>
