<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  dadosEscritos,
  primeiroDadoQueFalta,
} from '../../../carteira/dadosQueFaltam';
import CampoDoSeguro from '../CampoDoSeguro.vue';

// #2897 — os dados que faltam para cotar. Quando o agente da conta já
// perguntou à pessoa, só a lista do que falta (e a saída "Preencher você
// mesmo"). Sem agente, ou para quem resolveu preencher, um espaço por dado. O
// botão "Cotar com estes dados" é o passo da vez e mora no rodapé da gaveta:
// ele chama `cotar()` daqui, que diz o primeiro dado vazio e leva o foco até
// ele.
const props = defineProps({
  // Os nomes dos dados que faltam, na ordem em que aparecem.
  faltou: { type: Array, required: true },
  // O nome do agente que já perguntou à pessoa ('' = ninguém perguntou).
  perguntou: { type: String, default: '' },
  preenchendo: { type: Boolean, default: false },
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
        {{ ca(`DADO.${dado.toUpperCase()}`) }}
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
    <CampoDoSeguro
      v-for="dado in faltou"
      :id="idDo(dado)"
      :key="dado"
      type="text"
      autocomplete="off"
      data-carteira="dado-que-faltou"
      :data-dado="dado"
      :model-value="escritos[dado] ?? ''"
      :rotulo="ca(`DADO.${dado.toUpperCase()}`)"
      :falta="vazio === dado ? ca(`FALTA_DADO.${dado.toUpperCase()}`) : ''"
      @update:model-value="escrever(dado, $event)"
    />
  </form>
</template>
