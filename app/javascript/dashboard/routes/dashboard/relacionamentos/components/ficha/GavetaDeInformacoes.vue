<script setup>
import { toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFormularioDaPessoa } from '../../ficha/useFormularioDaPessoa';
import CamposDaPessoa from './CamposDaPessoa.vue';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — a gaveta "Alterar informações": o único lugar de edição da ficha.
// Abre com o que a pessoa tem hoje; "Salvar" confere e emite os dados prontos.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  pessoa: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['fechar', 'salvar']);

const { t } = useI18n();
const {
  formulario,
  erros,
  abrir,
  mudar,
  mudarRede,
  mudarExtra,
  dadosSeValido,
} = useFormularioDaPessoa();

watch(
  [toRef(props, 'aberta'), toRef(props, 'pessoa')],
  ([estaAberta, pessoa]) => {
    if (estaAberta && pessoa) abrir(pessoa);
  },
  { immediate: true }
);

const salvar = () => {
  const dados = dadosSeValido();
  if (dados) emit('salvar', dados);
};
</script>

<template>
  <GavetaLateral
    marca="gaveta-informacoes"
    largura="sm:w-[32rem]"
    :aberta="aberta && Boolean(formulario)"
    :titulo="t('RELACIONAMENTOS_FICHA.GAVETA.TITULO')"
    @fechar="emit('fechar')"
  >
    <CamposDaPessoa
      v-if="formulario"
      :formulario="formulario"
      :erros="erros"
      @mudar="mudar"
      @mudar-rede="mudarRede"
      @mudar-extra="mudarExtra"
    />
    <template #rodape>
      <Button
        data-relacionamentos="salvar-informacoes"
        size="lg"
        class="!min-h-12 !rounded-xl"
        :is-loading="salvando"
        :label="t('RELACIONAMENTOS_FICHA.GAVETA.SALVAR')"
        @click="salvar"
      />
      <Button
        slate
        faded
        size="lg"
        class="!min-h-12 !rounded-xl"
        :label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
        @click="emit('fechar')"
      />
    </template>
  </GavetaLateral>
</template>
