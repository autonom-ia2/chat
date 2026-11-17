<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { FALTAS } from '../../../carteira/ajustesDaRenovacao';
import {
  QUEM_COTA,
  QUEM_ENVIA,
  QUEM_RESPONDE,
  agenteForaDaCaixa,
  caixaEscolhida,
  porQueSoNinguem,
  roboCota,
} from '../../../carteira/cotacaoDaRenovacao';

// #2901 (E8) — "Cotação da renovação", o cartão de "Ajustar renovações" que só
// existe com a cotação ligada na conta. Quatro perguntas em palavras simples:
// quem faz a cotação, como a proposta sai, quem responde o cliente e por qual
// WhatsApp. As três últimas só aparecem quando o robô cota. A conta sem o
// Agente de Cotação, ou sem WhatsApp oficial, lê só "Ninguém, cotação manual"
// e a frase do porquê: nenhuma opção desligada. O nome do agente é o da conta.
// Antes de salvar, a tela avisa quando o agente vai responder e não está no
// WhatsApp escolhido. Embaixo, quantas cotações a conta fez no mês (só
// contagens, sem dinheiro).
//   v-model: os ajustes inteiros (só as escolhas da cotação mudam aqui)
const props = defineProps({
  modelValue: { type: Object, required: true },
  // { cotaSozinha, agente, caixas: [{ id, nome, liaLigada }] }
  conta: { type: Object, required: true },
  // { cotacoes, seguradorasComPreco } ou null
  consumo: { type: Object, default: null },
  falta: { type: String, default: '' },
  idDoAviso: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const tc = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.${chave}`, valores);
const id = useId();

const agente = computed(() => props.conta.agente || '');
const caixas = computed(() => props.conta.caixas ?? []);
const soNinguem = computed(() => porQueSoNinguem(props.conta));
const cota = computed(() => roboCota(props.modelValue));
const faltaCaixa = computed(() => props.falta === FALTAS.CAIXA);

const opcoesDeQuemCota = computed(() => [
  { value: QUEM_COTA.NINGUEM, label: tc('QUEM_COTA.NINGUEM') },
  { value: QUEM_COTA.ROBO, label: tc('QUEM_COTA.ROBO') },
  {
    value: QUEM_COTA.LIA,
    label: tc('QUEM_COTA.LIA', { agente: agente.value }),
  },
]);
const opcoesDeQuemEnvia = computed(() => [
  { value: QUEM_ENVIA.PESSOA, label: tc('QUEM_ENVIA.PESSOA') },
  { value: QUEM_ENVIA.SOZINHO, label: tc('QUEM_ENVIA.SOZINHO') },
]);
const opcoesDeQuemResponde = computed(() => [
  { value: QUEM_RESPONDE.EQUIPE, label: tc('QUEM_RESPONDE.EQUIPE') },
  {
    value: QUEM_RESPONDE.LIA,
    label: tc('QUEM_RESPONDE.LIA', { agente: agente.value }),
  },
]);
const opcoesDeCaixa = computed(() =>
  caixas.value.map(caixa => ({ value: caixa.id, label: caixa.nome }))
);

const apoioDoEnvio = computed(() =>
  props.modelValue.quemEnvia === QUEM_ENVIA.SOZINHO
    ? tc('QUEM_ENVIA.APOIO_SOZINHO')
    : tc('QUEM_ENVIA.APOIO_PESSOA')
);
const avisoDoAgente = computed(() =>
  agenteForaDaCaixa(props.modelValue, caixas.value)
    ? tc('AVISO_DO_AGENTE', {
        agente: agente.value,
        caixa: caixaEscolhida(caixas.value, props.modelValue.caixaId).nome,
      })
    : ''
);

const mudar = (campo, valor) =>
  emit('update:modelValue', { ...props.modelValue, [campo]: valor });

// Leva o foco ao WhatsApp, quando é ele que falta.
defineExpose({
  focar: () => document.getElementById(`${id}-caixa`)?.focus(),
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      v-if="soNinguem"
      data-carteira="cotacao-so-ninguem"
      :data-motivo="soNinguem"
      class="flex flex-col gap-2"
    >
      <p class="m-0 text-base text-n-slate-11">
        {{ tc('QUEM_COTA.PERGUNTA') }}
      </p>
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ tc('QUEM_COTA.NINGUEM') }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ tc(`SO_NINGUEM.${soNinguem}`) }}
      </p>
    </div>
    <template v-else>
      <p class="m-0 text-base text-n-slate-11">{{ tc('APOIO') }}</p>
      <div data-carteira="escolher-quem-cota" class="flex flex-col gap-2">
        <label :for="`${id}-quem-cota`" class="text-base text-n-slate-12">
          {{ tc('QUEM_COTA.PERGUNTA') }}
        </label>
        <ChoiceSelect
          :trigger-id="`${id}-quem-cota`"
          :model-value="modelValue.quemCota"
          :options="opcoesDeQuemCota"
          :aria-label="tc('QUEM_COTA.PERGUNTA')"
          wrap-selected
          @update:model-value="mudar('quemCota', $event)"
        />
      </div>
      <template v-if="cota">
        <div data-carteira="escolher-quem-envia" class="flex flex-col gap-2">
          <label :for="`${id}-quem-envia`" class="text-base text-n-slate-12">
            {{ tc('QUEM_ENVIA.PERGUNTA') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-quem-envia`"
            :model-value="modelValue.quemEnvia"
            :options="opcoesDeQuemEnvia"
            :aria-label="tc('QUEM_ENVIA.PERGUNTA')"
            wrap-selected
            @update:model-value="mudar('quemEnvia', $event)"
          />
          <p data-carteira="apoio-do-envio" class="m-0 text-sm text-n-slate-11">
            {{ apoioDoEnvio }}
          </p>
        </div>
        <div data-carteira="escolher-quem-responde" class="flex flex-col gap-2">
          <label :for="`${id}-quem-responde`" class="text-base text-n-slate-12">
            {{ tc('QUEM_RESPONDE.PERGUNTA') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-quem-responde`"
            :model-value="modelValue.quemResponde"
            :options="opcoesDeQuemResponde"
            :aria-label="tc('QUEM_RESPONDE.PERGUNTA')"
            wrap-selected
            @update:model-value="mudar('quemResponde', $event)"
          />
        </div>
        <div data-carteira="escolher-caixa" class="flex flex-col gap-2">
          <label :for="`${id}-caixa`" class="text-base text-n-slate-12">
            {{ tc('CAIXA.PERGUNTA') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-caixa`"
            :model-value="modelValue.caixaId"
            :options="opcoesDeCaixa"
            :aria-label="tc('CAIXA.PERGUNTA')"
            :placeholder="tc('CAIXA.ESCOLHA')"
            :invalid="faltaCaixa"
            :described-by="faltaCaixa ? idDoAviso : undefined"
            wrap-selected
            @update:model-value="mudar('caixaId', $event)"
          />
        </div>
        <Banner
          v-if="avisoDoAgente"
          color="amber"
          role="alert"
          data-carteira="aviso-do-agente"
        >
          {{ avisoDoAgente }}
        </Banner>
      </template>
    </template>

    <div
      v-if="consumo"
      data-carteira="consumo-de-cotacoes"
      class="flex flex-col gap-1 pt-4 border-t border-n-weak"
    >
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ tc('CONSUMO.COTACOES', { count: consumo.cotacoes }) }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ tc('CONSUMO.COM_PRECO', { count: consumo.seguradorasComPreco }) }}
      </p>
    </div>
  </div>
</template>
