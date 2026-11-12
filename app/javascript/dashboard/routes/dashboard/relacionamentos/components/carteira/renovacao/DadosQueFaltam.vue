<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  dadoOpcional,
  dadosEscritos,
  opcoesDoDado,
  primeiroDadoQueFalta,
  tipoDoCampo,
} from '../../../carteira/dadosQueFaltam';
import CampoDoSeguro from '../CampoDoSeguro.vue';
import EscolhaDoSeguro from '../EscolhaDoSeguro.vue';

// #2897 — os dados que faltam para cotar. Quando o agente da conta já
// perguntou à pessoa, só a lista do que falta (e a saída "Preencher você
// mesmo"). Sem agente, ou para quem resolveu preencher, um espaço por dado: o
// de resposta fechada (estado civil, onde o carro dorme…) é escolha única, com
// "Escolha" dentro enquanto está vazio; a data de nascimento é campo de data;
// os outros são texto. Quem dirige o carro pode ficar sem resposta. O botão
// "Cotar com estes dados" é o passo da vez e mora no rodapé da gaveta: ele
// chama `cotar()` daqui, que diz o primeiro dado obrigatório vazio e leva o
// foco até ele.
const props = defineProps({
  // Os nomes dos dados que faltam, na ordem em que aparecem.
  faltou: { type: Array, required: true },
  // O nome do agente que já perguntou à pessoa ('' = ninguém perguntou).
  perguntou: { type: String, default: '' },
  preenchendo: { type: Boolean, default: false },
  // O segurado é uma empresa: "A própria pessoa" não é quem dirige.
  seguradoEmpresa: { type: Boolean, default: false },
});
const emit = defineEmits(['preencher', 'cotar']);

const { t } = useI18n();
const ca = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`, valores);
const id = useId();
const idDo = dado => `${id}-${dado}`;

const escritos = ref({});
// O dado vazio que o último clique apontou ('' = nenhum).
const vazio = ref('');
const rotuloDo = dado => ca(`DADO.${dado.toUpperCase()}`);
const faltaDo = dado =>
  vazio.value === dado ? ca(`FALTA_DADO.${dado.toUpperCase()}`) : '';

// Cada dado com o que a tela precisa: o rótulo e, no de resposta fechada, as
// opções (`null` = texto livre).
const campos = computed(() =>
  props.faltou.map(dado => {
    const opcoes = opcoesDoDado(dado, { deEmpresa: props.seguradoEmpresa });
    return {
      dado,
      rotulo: dadoOpcional(dado)
        ? ca('OPCIONAL', { rotulo: rotuloDo(dado) })
        : rotuloDo(dado),
      opcoes:
        opcoes?.map(opcao => ({
          value: opcao,
          label: ca(`OPCAO.${dado.toUpperCase()}.${opcao.toUpperCase()}`),
        })) ?? null,
    };
  })
);

const escrever = (dado, valor) => {
  escritos.value = { ...escritos.value, [dado]: valor };
  if (vazio.value === dado) vazio.value = '';
};

const cotar = async () => {
  vazio.value = primeiroDadoQueFalta(props.faltou, escritos.value) ?? '';
  if (!vazio.value) {
    emit('cotar', dadosEscritos(props.faltou, escritos.value));
    return;
  }
  await nextTick();
  document.getElementById(idDo(vazio.value))?.focus();
};

defineExpose({ cotar });
</script>

<template>
  <div
    v-if="perguntou && !preenchendo"
    data-carteira="dados-que-faltam"
    class="flex flex-col gap-3"
  >
    <p class="m-0 text-base break-words text-n-slate-12">
      {{ ca('JA_PERGUNTOU', { agente: perguntou }) }}
    </p>
    <p :id="`${id}-o-que-falta`" class="m-0 text-base text-n-slate-11">
      {{ ca('O_QUE_FALTA') }}
    </p>
    <ul
      :aria-labelledby="`${id}-o-que-falta`"
      class="flex flex-col gap-1 m-0 ps-5 list-disc text-base text-n-slate-12"
    >
      <li v-for="dado in faltou" :key="dado" :data-dado="dado">
        {{ rotuloDo(dado) }}
      </li>
    </ul>
    <div>
      <Button
        link
        size="lg"
        data-carteira="preencher-os-dados"
        :label="ca('PREENCHER')"
        @click="emit('preencher')"
      />
    </div>
  </div>
  <form
    v-else
    data-carteira="dados-para-preencher"
    class="flex flex-col gap-4"
    novalidate
    @submit.prevent="cotar"
  >
    <p v-if="!perguntou" class="m-0 text-base text-n-slate-12">
      {{ ca('PERGUNTE') }}
    </p>
    <template v-for="campo in campos" :key="campo.dado">
      <EscolhaDoSeguro
        v-if="campo.opcoes"
        :id="idDo(campo.dado)"
        data-carteira="escolha-que-faltou"
        :data-dado="campo.dado"
        :model-value="escritos[campo.dado] ?? ''"
        :rotulo="campo.rotulo"
        :opcoes="campo.opcoes"
        :vazio="ca('ESCOLHA')"
        :falta="faltaDo(campo.dado)"
        @update:model-value="escrever(campo.dado, $event)"
      />
      <CampoDoSeguro
        v-else
        :id="idDo(campo.dado)"
        :type="tipoDoCampo(campo.dado)"
        autocomplete="off"
        data-carteira="dado-que-faltou"
        :data-dado="campo.dado"
        :model-value="escritos[campo.dado] ?? ''"
        :rotulo="campo.rotulo"
        :falta="faltaDo(campo.dado)"
        @update:model-value="escrever(campo.dado, $event)"
      />
    </template>
  </form>
</template>
