<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampoDeBusca from '../lista/CampoDeBusca.vue';
import MenuMaisAcoes from '../lista/MenuMaisAcoes.vue';
import { ORDENS_DE_SEGUROS } from '../../fonte/carteiraFonte';

// #2897 — a faixa de controles da aba Seguros: busca, ordem, "Mais filtros" e
// os dois atalhos discretos (Resultados e Ajustar renovações). Em 390 px os
// atalhos vão para o menu "⋯". A busca nunca fica mais estreita que o texto de
// exemplo dela: 26rem menos os 6rem das duas margens do campo dão 20rem para
// "Buscar por nome, placa ou documento" (cerca de 18,5rem); sem esse espaço, os
// atalhos descem para a linha de baixo.
const props = defineProps({
  busca: { type: String, default: '' },
  ordem: { type: String, required: true },
  filtrosAtivos: { type: Number, default: 0 },
});
const emit = defineEmits([
  'update:busca',
  'update:ordem',
  'abrirFiltros',
  'resultados',
  'ajustar',
]);

const { t } = useI18n();
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores);
const idDaOrdem = useId();

const opcoesDeOrdem = computed(() => [
  {
    value: ORDENS_DE_SEGUROS.VENCE_PRIMEIRO,
    label: ca('ORDENAR.VENCE_PRIMEIRO'),
  },
  { value: ORDENS_DE_SEGUROS.NOME, label: ca('ORDENAR.NOME') },
  { value: ORDENS_DE_SEGUROS.MAIS_NOVOS, label: ca('ORDENAR.MAIS_NOVOS') },
]);

const rotuloDosFiltros = computed(() =>
  props.filtrosAtivos
    ? ca('FILTROS.BOTAO_COM_CONTAGEM', { count: props.filtrosAtivos })
    : ca('FILTROS.BOTAO')
);

const ATALHOS = [
  { id: 'resultados', chave: 'RESULTADOS', icone: 'i-lucide-chart-column' },
  { id: 'ajustar', chave: 'AJUSTAR', icone: 'i-lucide-settings-2' },
];
// Cada atalho avisa a página com o próprio evento, escrito por extenso.
const AVISAR = {
  resultados: () => emit('resultados'),
  ajustar: () => emit('ajustar'),
};
const itensDoMenu = computed(() =>
  ATALHOS.map(({ id, chave, icone }) => ({ id, icone, rotulo: ca(chave) }))
);
</script>

<template>
  <div class="flex flex-wrap items-center min-w-0 gap-3">
    <div
      data-carteira="busca"
      class="w-full md:w-auto md:min-w-[26rem] md:flex-1"
    >
      <CampoDeBusca
        :model-value="busca"
        :placeholder="ca('BUSCA')"
        :placeholder-curto="ca('BUSCA_CURTA')"
        @update:model-value="emit('update:busca', $event)"
      />
    </div>
    <div class="flex items-center w-full gap-3 md:w-auto">
      <div class="flex items-center flex-1 min-w-0 gap-2 md:flex-none">
        <label
          :for="idDaOrdem"
          class="text-sm sr-only text-n-slate-11 sm:not-sr-only"
        >
          {{ ca('ORDENAR.ROTULO') }}
        </label>
        <ChoiceSelect
          :model-value="ordem"
          :options="opcoesDeOrdem"
          :trigger-id="idDaOrdem"
          :aria-label="ca('ORDENAR.ROTULO')"
          class="flex-1 min-w-0 md:flex-none"
          @update:model-value="emit('update:ordem', $event)"
        />
      </div>
      <Button
        slate
        faded
        class="shrink-0 whitespace-nowrap"
        icon="i-lucide-sliders-horizontal"
        data-carteira="mais-filtros"
        aria-haspopup="dialog"
        :label="rotuloDosFiltros"
        @click="emit('abrirFiltros')"
      />
      <MenuMaisAcoes
        class="sm:hidden"
        para-baixo
        :rotulo="ca('MAIS')"
        :itens="itensDoMenu"
        @escolher="AVISAR[$event]?.()"
      />
    </div>
    <div class="hidden gap-3 sm:flex">
      <Button
        v-for="atalho in ATALHOS"
        :key="atalho.id"
        slate
        faded
        class="shrink-0 whitespace-nowrap"
        :icon="atalho.icone"
        :data-carteira="atalho.id"
        :label="ca(atalho.chave)"
        @click="AVISAR[atalho.id]()"
      />
    </div>
  </div>
</template>
