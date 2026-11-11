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
const props = defineProps({
  busca: { type: String, default: '' },
  ordem: { type: String, required: true },
  filtrosAtivos: { type: Number, default: 0 },
  comFiltros: { type: Boolean, default: true },
  placeholder: { type: String, required: true },
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
  <div class="flex flex-wrap items-center gap-3">
    <CampoDeBusca
      class="w-full md:w-auto md:min-w-72 md:flex-1"
      :model-value="busca"
      :placeholder="placeholder"
      @update:model-value="emit('update:busca', $event)"
    />
    <div class="flex items-center gap-2">
      <label :for="idDaOrdem" class="text-sm text-n-slate-11">
        {{ t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO') }}
      </label>
      <ChoiceSelect
        :model-value="ordem"
        :options="opcoesDeOrdem"
        :trigger-id="idDaOrdem"
        :aria-label="t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO')"
        compact
        @update:model-value="emit('update:ordem', $event)"
      />
    </div>
    <Button
      v-if="comFiltros"
      slate
      faded
      class="min-h-11"
      icon="i-lucide-sliders-horizontal"
      data-relacionamentos="mais-filtros"
      aria-haspopup="dialog"
      :label="rotuloDosFiltros"
      @click="emit('abrirFiltros')"
    />
  </div>
</template>
