<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { ONDE, useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';

// #2897 — o seguro dentro da renovação dele: qual é, quando vence e o PDF da
// apólice (quando há).
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
    <p class="m-0 text-base break-words text-n-slate-12">
      {{
        tk('SEGURO_LINHA', {
          tipo: textos.tipo(seguro),
          seguradora: seguro.seguradora,
          numero: seguro.numero,
        })
      }}
    </p>
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
