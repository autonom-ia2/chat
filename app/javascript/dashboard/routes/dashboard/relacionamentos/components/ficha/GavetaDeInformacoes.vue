<script setup>
import { computed, ref, toRef, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { camposDaPessoa } from '../../ficha/atributos';
import { useFormularioDaPessoa } from '../../ficha/useFormularioDaPessoa';
import DialogoDeConfirmacao from '../carteira/DialogoDeConfirmacao.vue';
import CamposDaPessoa from './CamposDaPessoa.vue';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — a gaveta "Alterar informações": o único lugar de edição da ficha.
// Abre com o que a pessoa tem hoje; "Salvar" confere e emite os dados prontos.
// #3062 — a lista usa a mesma gaveta para "Editar" da linha e, com uma pessoa
// vazia, para "Nova pessoa" (`titulo` e `rotuloSalvar` trocam os textos).
// `errosDoServidor` ({ campo: chave do erro }) é o que o servidor recusou, como
// o e-mail ou o telefone repetido: fica embaixo do campo enquanto ele continuar
// com o mesmo valor, e some quando a pessoa corrige.
// #3062 — fechar pelo X, pelo Esc ou pelo fundo com algo escrito pergunta antes
// ("Sair sem salvar?", com "Continuar escrevendo"); sem nada mudado, fecha
// direto. "Cancelar" é a escolha de sair e fecha sem perguntar.
// #3075 — e os dados da ficha antiga: foto, país, "Sobre a pessoa", a empresa
// cadastrada (`comEmpresas`, com `buscarEmpresas` para a escolha) e os campos
// personalizados da conta (`definicoes`, com os `escolhidos` do configurador).
// "Salvar" emite o pedido inteiro (ficha/informacoes.js#pedidoParaSalvar).
// `empresaCadastrada` ({ id, nome }): a empresa nova que a fonte já cadastrou
// numa tentativa que parou no meio. A escolha passa a apontar para ela, e o
// próximo "Salvar" não cadastra outra.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  pessoa: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
  titulo: { type: String, default: '' },
  rotuloSalvar: { type: String, default: '' },
  marca: { type: String, default: 'gaveta-informacoes' },
  errosDoServidor: { type: Object, default: () => ({}) },
  comEmpresas: { type: Boolean, default: false },
  buscarEmpresas: { type: Function, default: null },
  definicoes: { type: Array, default: () => [] },
  escolhidos: { type: Array, default: () => [] },
  // #3082: chaves dos campos apagados, que não viram campo solto.
  guardadas: { type: Array, default: () => [] },
  empresaCadastrada: { type: Object, default: null },
});
const emit = defineEmits(['fechar', 'salvar']);

const { t } = useI18n();
const tiposDosCampos = () =>
  Object.fromEntries(
    props.definicoes.map(definicao => [
      definicao.attribute_key,
      definicao.attribute_display_type,
    ])
  );
const {
  inicial,
  formulario,
  erros,
  mexido,
  abrir,
  mudar,
  mudarRede,
  mudarAtributo,
  mudarEmpresa,
  dadosSeValido,
} = useFormularioDaPessoa({
  comEmpresas: () => props.comEmpresas,
  tiposDosCampos,
});

// A ordem dos campos sai do que a pessoa tinha ao abrir: escrever num campo
// não o faz pular de lugar.
const campos = computed(() =>
  inicial.value
    ? camposDaPessoa({
        definicoes: props.definicoes,
        escolhidos: props.escolhidos,
        guardadas: props.guardadas,
        valores: inicial.value.atributos,
      })
    : []
);

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

watch(toRef(props, 'empresaCadastrada'), cadastrada => {
  if (cadastrada && formulario.value?.empresaNova) {
    mudarEmpresa({ ...cadastrada, nova: false });
  }
});

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

const dialogoDeSair = useTemplateRef('dialogoDeSair');
const fecharOuPerguntar = () => {
  if (!mexido.value) {
    emit('fechar');
    return;
  }
  dialogoDeSair.value?.abrir();
};
const sairSemSalvar = () => {
  dialogoDeSair.value?.fechar();
  emit('fechar');
};

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
    @fechar="fecharOuPerguntar"
  >
    <CamposDaPessoa
      v-if="formulario"
      :formulario="formulario"
      :inicial="inicial"
      :erros="errosNaTela"
      :foto-atual="pessoa?.thumbnail ?? ''"
      :com-empresas="comEmpresas"
      :buscar-empresas="buscarEmpresas"
      :campos="campos"
      @mudar="mudar"
      @mudar-rede="mudarRede"
      @mudar-atributo="mudarAtributo"
      @mudar-empresa="mudarEmpresa"
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
  <DialogoDeConfirmacao
    ref="dialogoDeSair"
    marca="sair-sem-salvar"
    empilhado
    :titulo="t('RELACIONAMENTOS_FICHA.GAVETA.SAIR.TITULO')"
    :aviso="t('RELACIONAMENTOS_FICHA.GAVETA.SAIR.AVISO')"
    :confirmar="t('RELACIONAMENTOS_FICHA.GAVETA.SAIR.CONFIRMAR')"
    :voltar="t('RELACIONAMENTOS_FICHA.GAVETA.SAIR.VOLTAR')"
    @confirmar="sairSemSalvar"
  />
</template>
