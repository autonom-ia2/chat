<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  SITUACOES,
  faltaMotivo,
  renovacaoSoDeLeitura,
  situacaoDaRenovacao,
} from '../../carteira/situacaoDaRenovacao';

// #2898 — "Renovação" na gaveta do seguro: em que pé ela está (em que etapa do
// funil, ou como terminou), quem cuida e o caminho até o card no CRM. É
// leitura: "Renovou" e "Não renovou" ficam no rodapé da gaveta. Uma renovação
// perdida sem motivo (foi fechada pelo quadro do funil, que não pergunta)
// convida quem pode alterar a dizer o motivo. Quem não enxerga o card da
// renovação (ela chega sem `cardId`) só lê: sem convite e sem o caminho até o
// CRM. Só existe no seguro que tem renovação.
const props = defineProps({
  seguro: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
});
const emit = defineEmits(['abrirCard', 'dizerMotivo']);

const { t } = useI18n();
const tr = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.${chave}`, valores);
const idDoTitulo = useId();

const emQuePe = computed(() => {
  const { id, motivo, ...valores } = situacaoDaRenovacao(props.seguro);
  return id === SITUACOES.NAO_RENOVOU_MOTIVO
    ? tr(`SITUACAO.${id}`, {
        motivo: tr(`MOTIVO.NA_FRASE.${motivo.toUpperCase()}`),
      })
    : tr(`SITUACAO.${id}`, valores);
});
const convidaADizer = computed(
  () =>
    props.podeEditar &&
    faltaMotivo(props.seguro) &&
    !renovacaoSoDeLeitura(props.seguro)
);
</script>

<template>
  <section
    data-carteira="renovacao"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-3"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ tr('TITULO') }}
    </h3>
    <p
      data-carteira="situacao-da-renovacao"
      class="m-0 text-base break-words text-n-slate-12"
    >
      {{ emQuePe }}
    </p>
    <p
      v-if="seguro.renovacao.cuida"
      data-carteira="quem-cuida"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ tr('QUEM_CUIDA', { nome: seguro.renovacao.cuida }) }}
    </p>
    <div
      v-if="convidaADizer || seguro.renovacao.cardId"
      class="flex flex-wrap items-center gap-x-4 gap-y-2"
    >
      <Button
        v-if="convidaADizer"
        slate
        faded
        size="lg"
        class="whitespace-nowrap"
        data-carteira="dizer-o-motivo"
        :label="tr('DIZER_O_MOTIVO')"
        @click="emit('dizerMotivo')"
      />
      <Button
        v-if="seguro.renovacao.cardId"
        link
        size="lg"
        icon="i-lucide-external-link"
        class="whitespace-nowrap"
        data-carteira="abrir-no-crm"
        :label="tr('ABRIR_NO_CRM')"
        @click="emit('abrirCard', seguro.renovacao.cardId)"
      />
    </div>
  </section>
</template>
