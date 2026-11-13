<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import GavetaLateral from '../ficha/GavetaLateral.vue';
import { FILTROS_DE_SEGUROS_VAZIOS } from '../../fonte/carteiraFonte';
import { chaveDoTipo } from '../../carteira/tiposDeSeguro';

// #2897 — "Mais filtros" da aba Seguros: tipo de seguro e seguradora. "Ver
// resultado" aplica; "Limpar" tira os dois e fecha. Só oferece o que existe na
// carteira (`opcoes` vem da fonte).
const props = defineProps({
  aberta: { type: Boolean, default: false },
  filtros: { type: Object, default: () => ({ ...FILTROS_DE_SEGUROS_VAZIOS }) },
  opcoes: {
    type: Object,
    default: () => ({ tipos: [], seguradoras: [] }),
  },
});
const emit = defineEmits(['fechar', 'aplicar', 'limpar']);

const { t } = useI18n();
const ca = chave => t(`RELACIONAMENTOS_CARTEIRA.LISTA.FILTROS.${chave}`);
const idBase = useId();

const rascunho = ref({ ...FILTROS_DE_SEGUROS_VAZIOS });
watch(
  () => props.aberta,
  aberta => {
    if (aberta) {
      rascunho.value = { ...FILTROS_DE_SEGUROS_VAZIOS, ...props.filtros };
    }
  },
  { immediate: true }
);

const comQualquer = (chave, lista) => [
  { value: '', label: ca(chave) },
  ...lista,
];

const campos = computed(() => [
  {
    chave: 'tipo',
    rotulo: ca('TIPO'),
    opcoes: comQualquer(
      'TODOS',
      props.opcoes.tipos.map(tipo => ({
        value: tipo,
        label: t(chaveDoTipo(tipo)),
      }))
    ),
  },
  {
    chave: 'seguradora',
    rotulo: ca('SEGURADORA'),
    opcoes: comQualquer(
      'TODAS',
      props.opcoes.seguradoras.map(nome => ({ value: nome, label: nome }))
    ),
  },
]);

const escolher = (chave, valor) => {
  rascunho.value = { ...rascunho.value, [chave]: valor };
};
</script>

<template>
  <GavetaLateral
    marca="gaveta-filtros"
    :aberta="aberta"
    :titulo="ca('TITULO')"
    @fechar="emit('fechar')"
  >
    <div data-carteira="filtros" class="flex flex-col gap-5">
      <div
        v-for="campo in campos"
        :key="campo.chave"
        class="flex flex-col gap-2"
      >
        <label
          :for="`${idBase}-${campo.chave}`"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ campo.rotulo }}
        </label>
        <ChoiceSelect
          :model-value="rascunho[campo.chave]"
          :options="campo.opcoes"
          :trigger-id="`${idBase}-${campo.chave}`"
          :aria-label="campo.rotulo"
          @update:model-value="escolher(campo.chave, $event)"
        />
      </div>
    </div>
    <template #rodape>
      <Button
        size="lg"
        data-carteira="ver-resultado"
        :label="ca('VER_RESULTADO')"
        @click="emit('aplicar', { ...rascunho })"
      />
      <Button
        slate
        faded
        size="lg"
        :label="ca('LIMPAR')"
        @click="emit('limpar')"
      />
    </template>
  </GavetaLateral>
</template>
