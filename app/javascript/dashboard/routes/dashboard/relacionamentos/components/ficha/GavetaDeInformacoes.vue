<script setup>
import { computed, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFormularioDaPessoa } from '../../ficha/useFormularioDaPessoa';
import CamposDaPessoa from './CamposDaPessoa.vue';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — a gaveta "Alterar informações": o único lugar de edição da ficha.
// Abre com o que a pessoa tem hoje; "Salvar" confere e emite os dados prontos.
// #3062 — a lista usa a mesma gaveta para "Editar" da linha e, com uma pessoa
// vazia, para "Nova pessoa" (`titulo` e `rotuloSalvar` trocam os textos).
// `errosDoServidor` ({ campo: chave do erro }) é o que o servidor recusou, como
// o e-mail ou o telefone repetido: fica embaixo do campo enquanto ele continuar
// com o mesmo valor, e some quando a pessoa corrige.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  pessoa: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
  titulo: { type: String, default: '' },
  rotuloSalvar: { type: String, default: '' },
  marca: { type: String, default: 'gaveta-informacoes' },
  errosDoServidor: { type: Object, default: () => ({}) },
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

const recusados = ref({});

// Só na transição fechada -> aberta: a pessoa pode mudar com a gaveta aberta
// (Marcar como cliente, por exemplo), e isso não pode apagar o que foi digitado.
watch(
  toRef(props, 'aberta'),
  (estaAberta, estavaAberta) => {
    if (!estaAberta || estavaAberta || !props.pessoa) return;
    abrir(props.pessoa);
    recusados.value = {};
  },
  { immediate: true }
);

// Cada recusa guarda o valor que o campo tinha: o aviso vale só para ele.
watch(toRef(props, 'errosDoServidor'), novos => {
  recusados.value = Object.fromEntries(
    Object.entries(novos).map(([campo, erro]) => [
      campo,
      { erro, valor: formulario.value?.[campo] },
    ])
  );
});

// O que o próprio formulário cobra vem antes do que o servidor recusou.
const errosNaTela = computed(() => ({
  ...Object.fromEntries(
    Object.entries(recusados.value)
      .filter(([campo, { valor }]) => formulario.value?.[campo] === valor)
      .map(([campo, { erro }]) => [campo, erro])
  ),
  ...erros.value,
}));

const salvar = () => {
  const dados = dadosSeValido();
  if (dados) emit('salvar', dados);
};
</script>

<template>
  <GavetaLateral
    :marca="marca"
    largura="sm:w-[32rem]"
    :aberta="aberta && Boolean(formulario)"
    :titulo="titulo || t('RELACIONAMENTOS_FICHA.GAVETA.TITULO')"
    @fechar="emit('fechar')"
  >
    <CamposDaPessoa
      v-if="formulario"
      :formulario="formulario"
      :erros="errosNaTela"
      @mudar="mudar"
      @mudar-rede="mudarRede"
      @mudar-extra="mudarExtra"
    />
    <template #rodape>
      <Button
        data-relacionamentos="salvar-informacoes"
        size="lg"
        :is-loading="salvando"
        :label="rotuloSalvar || t('RELACIONAMENTOS_FICHA.GAVETA.SALVAR')"
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
