<script setup>
import { toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFormularioDaEmpresa } from '../../ficha/useFormularioDaEmpresa';
import CampoDeTexto from './CampoDeTexto.vue';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — a gaveta "Alterar" da empresa: nome, CNPJ e site. Abre com o que a
// empresa tem hoje; "Salvar" confere e emite os dados prontos.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  empresa: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['fechar', 'salvar']);

const { t } = useI18n();
const { formulario, erros, abrir, mudar, dadosSeValido } =
  useFormularioDaEmpresa();

// Só na transição fechada -> aberta: a empresa pode ser trocada com a gaveta
// aberta, e isso não pode apagar o que a pessoa digitou.
watch(
  toRef(props, 'aberta'),
  (estaAberta, estavaAberta) => {
    if (estaAberta && !estavaAberta && props.empresa) abrir(props.empresa);
  },
  { immediate: true }
);

const ra = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);
const mensagem = campo => (campo ? ra(`ERRO.${campo}`) : '');

const CAMPOS = [
  { campo: 'nome', rotulo: 'NOME', foco: true },
  { campo: 'cnpj', rotulo: 'CNPJ', modo: 'numeric' },
  { campo: 'site', rotulo: 'SITE' },
];

const salvar = () => {
  const dados = dadosSeValido();
  if (dados) emit('salvar', dados);
};
</script>

<template>
  <GavetaLateral
    marca="gaveta-empresa"
    :aberta="aberta && Boolean(formulario)"
    :titulo="t('RELACIONAMENTOS_FICHA.EMPRESA.GAVETA_TITULO')"
    @fechar="emit('fechar')"
  >
    <form
      v-if="formulario"
      class="flex flex-col gap-5"
      novalidate
      @submit.prevent
    >
      <CampoDeTexto
        v-for="item in CAMPOS"
        :key="item.campo"
        :model-value="formulario[item.campo]"
        :rotulo="ra(item.rotulo)"
        :inputmode="item.modo"
        :data-foco="item.foco ? '' : undefined"
        :erro="mensagem(erros[item.campo])"
        @update:model-value="valor => mudar(item.campo, valor)"
      />
    </form>
    <template #rodape>
      <Button
        data-relacionamentos="salvar-empresa"
        size="lg"
        :is-loading="salvando"
        :label="ra('SALVAR')"
        @click="salvar"
      />
      <Button
        slate
        faded
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
        @click="emit('fechar')"
      />
    </template>
  </GavetaLateral>
</template>
