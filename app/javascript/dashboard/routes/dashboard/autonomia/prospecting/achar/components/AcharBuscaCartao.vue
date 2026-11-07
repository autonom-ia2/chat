<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — uma busca feita, na porta ("Suas últimas buscas") e em "Suas buscas"
// (molde automacoes/livre/components/LivreLinha.vue, sem interruptor). O cartão
// abre a busca, e "Abrir" fica explícito. Rodada 2: menu "Mais" (só Editar)
// com "Buscar de novo", "Baixar planilha" e "Apagar".
const props = defineProps({
  titulo: { type: String, required: true },
  fato: { type: String, required: true },
  feitaPor: { type: String, default: '' },
  compacto: { type: Boolean, default: false },
  comMais: { type: Boolean, default: false },
  maisAberto: { type: Boolean, default: false },
  // Rodada 4: "Apagar" só nas buscas da própria pessoa, também para a gestora.
  podeApagar: { type: Boolean, default: true },
});
const emit = defineEmits(['abrir', 'mais', 'acao']);

const TODAS_AS_ACOES = [
  { id: 'buscarDeNovo', chave: 'BUSCAR_DE_NOVO', icone: 'i-lucide-refresh-cw' },
  { id: 'baixar', chave: 'BAIXAR', icone: 'i-lucide-download' },
  { id: 'apagar', chave: 'APAGAR', icone: 'i-lucide-trash-2', perigo: true },
];
const acoes = computed(() =>
  TODAS_AS_ACOES.filter(acao => acao.id !== 'apagar' || props.podeApagar)
);
</script>

<template>
  <li
    class="flex flex-col gap-3 p-5 transition border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6"
    :class="props.compacto ? '' : 'sm:flex-row sm:items-center'"
    data-busca
  >
    <button
      type="button"
      class="flex flex-col flex-1 min-w-0 gap-1 p-0 rounded-lg text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('abrir')"
    >
      <span class="text-lg font-semibold break-words text-n-slate-12">
        {{ titulo }}
      </span>
      <span class="text-sm text-n-slate-11">{{ fato }}</span>
      <span
        v-if="feitaPor"
        class="flex items-center gap-1.5 text-sm text-n-slate-11"
        data-feita-por
      >
        <span class="i-lucide-user size-4" aria-hidden="true" />
        {{ feitaPor }}
      </span>
    </button>
    <div
      class="flex items-center self-start gap-2 shrink-0"
      :class="props.compacto ? '' : 'sm:self-center'"
    >
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.ABRIR')"
        :aria-label="
          $t('PROSPECTING_ACHAR.COMUM.ABRIR_ROTULO', { nome: titulo })
        "
        slate
        faded
        class="!min-h-11 !rounded-xl"
        data-abrir
        @click="emit('abrir')"
      />
      <div v-if="comMais" class="relative">
        <Button
          :label="$t('PROSPECTING_ACHAR.COMUM.MAIS')"
          icon="i-lucide-ellipsis"
          slate
          faded
          :aria-label="$t('PROSPECTING_ACHAR.BUSCAS.MAIS', { nome: titulo })"
          :aria-expanded="maisAberto"
          class="!min-h-11 !rounded-xl"
          data-mais-busca
          @click="emit('mais')"
        />
        <ul
          v-if="maisAberto"
          role="menu"
          class="absolute z-20 flex flex-col w-60 gap-0.5 p-1 m-0 mt-2 list-none border shadow-lg top-full start-0 sm:start-auto sm:end-0 rounded-xl border-n-weak bg-n-solid-1"
          data-menu-busca
        >
          <li v-for="acao in acoes" :key="acao.id" role="none">
            <button
              type="button"
              role="menuitem"
              class="flex items-center w-full gap-2 px-3 text-base rounded-lg text-start min-h-11 hover:bg-n-slate-3"
              :class="acao.perigo ? 'text-n-ruby-11' : 'text-n-slate-12'"
              @click="emit('acao', acao.id)"
            >
              <span class="size-4" :class="acao.icone" aria-hidden="true" />
              {{ $t(`PROSPECTING_ACHAR.BUSCAS.${acao.chave}`) }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </li>
</template>
