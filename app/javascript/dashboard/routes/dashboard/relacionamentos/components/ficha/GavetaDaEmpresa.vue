<script setup>
import { computed, toRef, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { camposDaEmpresa } from '../../ficha/atributos';
import { useFormularioDaEmpresa } from '../../ficha/useFormularioDaEmpresa';
import DialogoDeConfirmacao from '../carteira/DialogoDeConfirmacao.vue';
import CampoDeTexto from './CampoDeTexto.vue';
import CamposDaConta from './CamposDaConta.vue';
import FotoDaPessoa from './FotoDaPessoa.vue';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — a gaveta "Alterar" da empresa. Abre com o que a empresa tem hoje;
// "Salvar" confere e emite o pedido pronto.
// #3078 — com tudo o que a ficha antiga de Empresas mudava: a foto (no topo,
// quadrada como no cabeçalho), nome, CNPJ, site, cidade, "O que a empresa faz" e
// os campos personalizados da empresa com o controle do tipo de cada um
// (`definicoes`, com os `escolhidos` do configurador). A lista usa a mesma
// gaveta para "Nova empresa": com `empresa` vazia (`{}`), `titulo` e
// `rotuloSalvar` trocam os textos. Fechar pelo X, pelo Esc ou pelo fundo com
// algo escrito pergunta antes ("Sair sem salvar?"); "Cancelar" fecha direto.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  empresa: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
  titulo: { type: String, default: '' },
  rotuloSalvar: { type: String, default: '' },
  marca: { type: String, default: 'gaveta-empresa' },
  definicoes: { type: Array, default: () => [] },
  escolhidos: { type: Array, default: () => [] },
  // #3078 — uma frase no topo da gaveta ("Já criada: …" da Nova empresa).
  aviso: { type: String, default: '' },
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
  mudarAtributo,
  dadosSeValido,
} = useFormularioDaEmpresa({ tiposDosCampos });

// Só na transição fechada -> aberta: a empresa pode ser trocada com a gaveta
// aberta, e isso não pode apagar o que a pessoa digitou.
watch(
  toRef(props, 'aberta'),
  (estaAberta, estavaAberta) => {
    if (estaAberta && !estavaAberta && props.empresa) abrir(props.empresa);
  },
  { immediate: true }
);

// A ordem dos campos sai do que a empresa tinha ao abrir: escrever num campo
// não o faz pular de lugar.
const campos = computed(() =>
  inicial.value
    ? camposDaEmpresa({
        definicoes: props.definicoes,
        escolhidos: props.escolhidos,
        valores: inicial.value.atributos,
      })
    : []
);

const ra = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);
const re = chave => t(`RELACIONAMENTOS_FICHA.EMPRESA.GAVETA.${chave}`);
const mensagem = campo => (campo ? ra(`ERRO.${campo}`) : '');

const NOME_MAXIMO = 100;
const SOBRE_MAXIMO = 1000;
const CAMPOS = [
  { campo: 'nome', rotulo: ra('NOME'), foco: true, maximo: NOME_MAXIMO },
  { campo: 'cnpj', rotulo: ra('CNPJ'), modo: 'numeric' },
  {
    campo: 'site',
    rotulo: ra('SITE'),
    modo: 'url',
    exemplo: ra('ATRIBUTO.LINK_EXEMPLO'),
  },
  { campo: 'cidade', rotulo: ra('CIDADE') },
];

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
    :titulo="titulo || t('RELACIONAMENTOS_FICHA.EMPRESA.GAVETA_TITULO')"
    @fechar="fecharOuPerguntar"
  >
    <form
      v-if="formulario"
      class="flex flex-col gap-5"
      novalidate
      @submit.prevent
    >
      <p
        v-if="aviso"
        data-relacionamentos="aviso-da-gaveta"
        role="status"
        class="m-0 rounded-xl bg-n-amber-2 px-4 py-3 text-base text-n-amber-11"
      >
        {{ aviso }}
      </p>
      <FotoDaPessoa
        marca="foto-da-empresa"
        :redonda="false"
        :nome="formulario.nome"
        :atual="empresa?.thumbnail ?? ''"
        :foto="formulario.foto"
        @mudar="foto => mudar('foto', foto)"
      />
      <CampoDeTexto
        v-for="item in CAMPOS"
        :key="item.campo"
        :model-value="formulario[item.campo]"
        :rotulo="item.rotulo"
        :inputmode="item.modo"
        :placeholder="item.exemplo"
        :maxlength="item.maximo"
        :data-foco="item.foco ? '' : undefined"
        :data-campo="item.campo"
        :erro="mensagem(erros[item.campo])"
        @update:model-value="valor => mudar(item.campo, valor)"
      />
      <CampoDeTexto
        :model-value="formulario.sobre"
        :rotulo="re('SOBRE')"
        :linhas="3"
        :maxlength="SOBRE_MAXIMO"
        :placeholder="re('SOBRE_EXEMPLO')"
        :ajuda="re('SOBRE_AJUDA')"
        data-relacionamentos="sobre-a-empresa"
        @update:model-value="texto => mudar('sobre', texto)"
      />
      <CamposDaConta
        v-if="campos.length"
        :campos="campos"
        :valores="formulario.atributos"
        :iniciais="inicial.atributos"
        :erros="erros"
        @mudar="mudarAtributo"
      />
    </form>
    <template #rodape>
      <Button
        data-relacionamentos="salvar-empresa"
        size="lg"
        :is-loading="salvando"
        :label="rotuloSalvar || ra('SALVAR')"
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
    marca="sair-sem-salvar-empresa"
    empilhado
    :titulo="ra('SAIR.TITULO')"
    :aviso="ra('SAIR.AVISO')"
    :confirmar="ra('SAIR.CONFIRMAR')"
    :voltar="ra('SAIR.VOLTAR')"
    @confirmar="sairSemSalvar"
  />
</template>
