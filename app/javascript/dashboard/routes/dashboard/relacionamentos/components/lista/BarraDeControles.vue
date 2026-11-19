<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { ORDENS } from '../../fonte/listaFonte';
import CampoDeBusca from './CampoDeBusca.vue';

// #2894 — a faixa de controles acima da lista: busca, ordem e "Mais filtros".
// Na aba Empresas não há "Mais filtros" (empresa, etiqueta e cidade são de
// pessoa).
// #3057 — busca, ordem e "Mais filtros" na mesma altura (h-10) e no mesmo
// canto; a área de toque do botão continua com 44 px (o ::before).
// #3062 — `gruposDeOrdem` (lista/ordens.js): a aba Pessoas ganha as sete ordens
// da lista de contatos de hoje, agrupadas por campo e nos dois sentidos. Sem
// eles, ficam as três de sempre.
const props = defineProps({
  busca: { type: String, default: '' },
  ordem: { type: String, required: true },
  gruposDeOrdem: { type: Array, default: () => [] },
  filtrosAtivos: { type: Number, default: 0 },
  comFiltros: { type: Boolean, default: true },
  placeholder: { type: String, required: true },
  placeholderCurto: { type: String, default: '' },
});
const emit = defineEmits(['update:busca', 'update:ordem', 'abrirFiltros']);

const { t } = useI18n();
const idDaOrdem = useId();

const opcoesDeOrdem = computed(() => [
  {
    value: ORDENS.ULTIMA_CONVERSA,
    label: t('RELACIONAMENTOS.LISTA.ORDENAR.ULTIMA_CONVERSA'),
  },
  { value: ORDENS.NOME, label: t('RELACIONAMENTOS.LISTA.ORDENAR.NOME') },
  {
    value: ORDENS.MAIS_NOVOS,
    label: t('RELACIONAMENTOS.LISTA.ORDENAR.MAIS_NOVOS'),
  },
]);

const rotuloDosFiltros = computed(() =>
  props.filtrosAtivos
    ? t('RELACIONAMENTOS.LISTA.FILTROS.BOTAO_COM_CONTAGEM', {
        count: props.filtrosAtivos,
      })
    : t('RELACIONAMENTOS.LISTA.FILTROS.BOTAO')
);
</script>

<template>
  <div class="flex flex-wrap items-center min-w-0 gap-3">
    <CampoDeBusca
      class="w-full md:w-auto md:min-w-72 md:flex-1"
      :model-value="busca"
      :placeholder="placeholder"
      :placeholder-curto="placeholderCurto"
      @update:model-value="emit('update:busca', $event)"
    />
    <div class="flex items-center w-full gap-3 md:w-auto">
      <div class="flex items-center flex-1 min-w-0 gap-2 md:flex-none">
        <label
          :for="idDaOrdem"
          class="text-sm sr-only text-n-slate-11 sm:not-sr-only"
        >
          {{ t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO') }}
        </label>
        <ChoiceSelect
          :model-value="ordem"
          :options="gruposDeOrdem.length ? [] : opcoesDeOrdem"
          :groups="gruposDeOrdem"
          :trigger-id="idDaOrdem"
          :aria-label="t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO')"
          data-relacionamentos="ordem"
          class="flex-1 min-w-0 md:flex-none"
          @update:model-value="emit('update:ordem', $event)"
        />
      </div>
      <Button
        v-if="comFiltros"
        slate
        faded
        class="relative shrink-0 whitespace-nowrap before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5"
        icon="i-lucide-sliders-horizontal"
        data-relacionamentos="mais-filtros"
        aria-haspopup="dialog"
        :label="rotuloDosFiltros"
        @click="emit('abrirFiltros')"
      />
    </div>
  </div>
</template>
