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
  SO_NINGUEM,
  agenteForaDaCaixa,
  caixaDistribui,
  caixaEscolhida,
  nomeDaCaixaNaFrase,
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
// WhatsApp escolhido, ou quando esse WhatsApp entrega toda conversa nova a
// alguém da equipe (aí o agente não responde). Embaixo, quantas cotações a
// conta fez no mês (só contagens, sem dinheiro).
//   v-model: os ajustes inteiros (só as escolhas da cotação mudam aqui)
const props = defineProps({
  modelValue: { type: Object, required: true },
  // { cotaSozinha, agente, caixas: [{ id, nome, liaLigada, distribui }] }
  conta: { type: Object, required: true },
  // { cotacoes, seguradorasComPreco } ou null
  consumo: { type: Object, default: null },
  falta: { type: String, default: '' },
  idDoAviso: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();

const agente = computed(() => props.conta.agente || '');
const caixas = computed(() => props.conta.caixas ?? []);
const soNinguem = computed(() => porQueSoNinguem(props.conta));
// Por que só "Ninguém", pela chave inteira do catálogo.
const POR_QUE_SO_NINGUEM = {
  [SO_NINGUEM.SEM_AGENTE]: () =>
    t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.SO_NINGUEM.SEM_AGENTE'),
  [SO_NINGUEM.SEM_CAIXA]: () =>
    t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.SO_NINGUEM.SEM_CAIXA'),
};
const fraseDoSoNinguem = computed(() =>
  soNinguem.value ? POR_QUE_SO_NINGUEM[soNinguem.value]() : ''
);
const cota = computed(() => roboCota(props.modelValue));
const faltaCaixa = computed(() => props.falta === FALTAS.CAIXA);

const opcoesDeQuemCota = computed(() => [
  {
    value: QUEM_COTA.NINGUEM,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.NINGUEM'),
  },
  {
    value: QUEM_COTA.ROBO,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.ROBO'),
  },
]);
const opcoesDeQuemEnvia = computed(() => [
  {
    value: QUEM_ENVIA.PESSOA,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.PESSOA'),
  },
  {
    value: QUEM_ENVIA.SOZINHO,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.SOZINHO'),
  },
]);
const opcoesDeQuemResponde = computed(() => [
  {
    value: QUEM_RESPONDE.EQUIPE,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_RESPONDE.EQUIPE'),
  },
  {
    value: QUEM_RESPONDE.LIA,
    label: t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_RESPONDE.LIA', {
      agente: agente.value,
    }),
  },
]);
const opcoesDeCaixa = computed(() =>
  caixas.value.map(caixa => ({ value: caixa.id, label: caixa.nome }))
);

const apoioDoEnvio = computed(() =>
  props.modelValue.quemEnvia === QUEM_ENVIA.SOZINHO
    ? t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.APOIO_SOZINHO')
    : t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.APOIO_PESSOA')
);
const avisoDoAgente = computed(() => {
  if (!agenteForaDaCaixa(props.modelValue, caixas.value)) return '';
  const caixa = nomeDaCaixaNaFrase(
    caixaEscolhida(caixas.value, props.modelValue.caixaId)?.nome
  );
  const chave = caixa ? 'AVISO_DO_AGENTE' : 'AVISO_DO_AGENTE_SEM_NOME';
  return t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.${chave}`, {
    agente: agente.value,
    caixa,
  });
});

const avisoDaDistribuicao = computed(() =>
  caixaDistribui(props.modelValue, caixas.value)
    ? t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.AVISO_DA_DISTRIBUICAO', {
        agente: agente.value,
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
        {{ t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.PERGUNTA') }}
      </p>
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.NINGUEM') }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ fraseDoSoNinguem }}
      </p>
    </div>
    <template v-else>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.APOIO') }}
      </p>
      <div data-carteira="escolher-quem-cota" class="flex flex-col gap-2">
        <label :for="`${id}-quem-cota`" class="text-base text-n-slate-12">
          {{ t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.PERGUNTA') }}
        </label>
        <ChoiceSelect
          :trigger-id="`${id}-quem-cota`"
          :model-value="modelValue.quemCota"
          :options="opcoesDeQuemCota"
          :aria-label="
            t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_COTA.PERGUNTA')
          "
          wrap-selected
          @update:model-value="mudar('quemCota', $event)"
        />
      </div>
      <template v-if="cota">
        <div data-carteira="escolher-quem-envia" class="flex flex-col gap-2">
          <label :for="`${id}-quem-envia`" class="text-base text-n-slate-12">
            {{
              t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.PERGUNTA')
            }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-quem-envia`"
            :model-value="modelValue.quemEnvia"
            :options="opcoesDeQuemEnvia"
            :aria-label="
              t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_ENVIA.PERGUNTA')
            "
            wrap-selected
            @update:model-value="mudar('quemEnvia', $event)"
          />
          <p data-carteira="apoio-do-envio" class="m-0 text-sm text-n-slate-11">
            {{ apoioDoEnvio }}
          </p>
        </div>
        <div data-carteira="escolher-quem-responde" class="flex flex-col gap-2">
          <label :for="`${id}-quem-responde`" class="text-base text-n-slate-12">
            {{
              t(
                'RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_RESPONDE.PERGUNTA'
              )
            }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-quem-responde`"
            :model-value="modelValue.quemResponde"
            :options="opcoesDeQuemResponde"
            :aria-label="
              t(
                'RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.QUEM_RESPONDE.PERGUNTA'
              )
            "
            wrap-selected
            @update:model-value="mudar('quemResponde', $event)"
          />
        </div>
        <div data-carteira="escolher-caixa" class="flex flex-col gap-2">
          <label :for="`${id}-caixa`" class="text-base text-n-slate-12">
            {{ t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.CAIXA.PERGUNTA') }}
          </label>
          <ChoiceSelect
            :trigger-id="`${id}-caixa`"
            :model-value="modelValue.caixaId"
            :options="opcoesDeCaixa"
            :aria-label="
              t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.CAIXA.PERGUNTA')
            "
            :placeholder="
              t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.CAIXA.ESCOLHA')
            "
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
        <Banner
          v-if="avisoDaDistribuicao"
          color="amber"
          role="alert"
          data-carteira="aviso-da-distribuicao"
        >
          {{ avisoDaDistribuicao }}
        </Banner>
      </template>
    </template>

    <div
      v-if="consumo"
      data-carteira="consumo-de-cotacoes"
      class="flex flex-col gap-1 pt-4 border-t border-n-weak"
    >
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{
          t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.CONSUMO.COTACOES', {
            count: consumo.cotacoes,
          })
        }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          t('RELACIONAMENTOS_CARTEIRA.AJUSTES.COTACAO.CONSUMO.COM_PRECO', {
            count: consumo.seguradorasComPreco,
          })
        }}
      </p>
    </div>
  </div>
</template>
