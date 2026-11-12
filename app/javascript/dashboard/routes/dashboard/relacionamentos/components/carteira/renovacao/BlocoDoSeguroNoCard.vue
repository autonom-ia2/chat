<script setup>
import { useId } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { ONDE, useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';

// #2897 — o seguro dentro da renovação dele: qual é, quando vence e o PDF da
// apólice (quando há). O número da apólice entra por slot do <I18nT>, num
// pedaço que não quebra no hífen.
defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['verApolice']);

const { t } = useI18n();
const tk = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.CARD.${chave}`, valores);
const textos = useTextosDoSeguro();
const id = useId();
</script>

<template>
  <section
    data-carteira="seguro-da-renovacao"
    :aria-labelledby="id"
    class="flex flex-col gap-2"
  >
    <h3 :id="id" class="m-0 text-base font-semibold text-n-slate-12">
      {{ tk('SEGURO') }}
    </h3>
    <I18nT
      keypath="RELACIONAMENTOS_CARTEIRA.RENOVACAO.CARD.SEGURO_LINHA"
      tag="p"
      scope="global"
      class="m-0 text-base break-words text-n-slate-12"
    >
      <template #tipo>{{ textos.tipo(seguro) }}</template>
      <template #seguradora>{{ seguro.seguradora }}</template>
      <template #numero>
        <span data-carteira="numero-da-apolice" class="whitespace-nowrap">
          {{ textos.numero(seguro) }}
        </span>
      </template>
    </I18nT>
    <p class="m-0 text-base text-n-slate-11">
      {{ textos.quando(seguro, agora, ONDE.FICHA) }}
    </p>
    <div v-if="seguro.temPdf">
      <Button
        link
        size="lg"
        data-carteira="ver-apolice"
        :label="tk('VER_APOLICE')"
        @click="emit('verApolice')"
      />
    </div>
  </section>
</template>
