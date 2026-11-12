<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { SELOS, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { iconeDoTipo } from '../../carteira/tiposDeSeguro';
import { ONDE, useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SeloDoSeguro from './SeloDoSeguro.vue';

// #2897 — um seguro no bloco Seguros da ficha: tipo, selo, seguradora e número
// (quando o seguro tem número), quando vence e o botão do PDF ("Ver PDF", ou
// "Guardar PDF" quando falta e quem olha pode guardar). Clicar na linha abre a
// gaveta do seguro: o botão do tipo estica a área de clique; o botão do PDF
// fica por cima. Em tela estreita "Guardar PDF" desce para a linha de baixo,
// inteiro: ao lado ele espremeria o texto.
const props = defineProps({
  seguro: { type: Object, required: true },
  podeGuardar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'pdf', 'guardar']);

const { t } = useI18n();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.FICHA.${chave}`, valores);
const textos = useTextosDoSeguro();

const tipo = computed(() => textos.tipo(props.seguro));
const cancelado = computed(
  () => seloDoSeguro(props.seguro, props.agora) === SELOS.CANCELADO
);
const corDasLinhas = computed(() =>
  cancelado.value ? 'text-n-slate-10' : 'text-n-slate-11'
);
</script>

<template>
  <li
    data-carteira="seguro"
    :data-apolice="seguro.id"
    class="relative flex flex-wrap items-center min-w-0 gap-3 p-3 transition-colors border rounded-xl border-n-weak sm:p-4 hover:border-n-blue-6 hover:bg-n-alpha-1"
  >
    <span
      class="flex items-center justify-center rounded-full size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
      aria-hidden="true"
    >
      <span class="size-5" :class="iconeDoTipo(seguro.tipo)" />
    </span>
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <button
          type="button"
          :aria-label="tf('ABRIR', { tipo })"
          class="p-0 text-base font-semibold break-words bg-transparent border-0 text-start after:absolute after:inset-0 after:rounded-xl focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:outline-n-brand"
          :class="cancelado ? 'text-n-slate-11' : 'text-n-slate-12'"
          @click="emit('abrir', seguro)"
        >
          {{ tipo }}
        </button>
        <SeloDoSeguro :seguro="seguro" :agora="agora" />
      </div>
      <I18nT
        v-if="seguro.numero"
        keypath="RELACIONAMENTOS_CARTEIRA.FICHA.SEGURADORA_E_NUMERO"
        tag="p"
        scope="global"
        class="m-0 text-sm break-words"
        :class="corDasLinhas"
      >
        <template #seguradora>{{ seguro.seguradora }}</template>
        <template #numero>
          <span data-carteira="numero-da-apolice" class="whitespace-nowrap">
            {{ textos.numero(seguro) }}
          </span>
        </template>
      </I18nT>
      <p v-else class="m-0 text-sm break-words" :class="corDasLinhas">
        {{ seguro.seguradora }}
      </p>
      <p class="m-0 text-sm break-words" :class="corDasLinhas">
        {{ textos.quando(seguro, agora, ONDE.FICHA) }}
      </p>
    </div>
    <Button
      v-if="seguro.temPdf"
      slate
      faded
      size="lg"
      class="relative z-10 shrink-0"
      icon="i-lucide-file-text"
      data-carteira="seguro-pdf"
      :label="tf('VER_PDF')"
      :aria-label="tf('VER_PDF_DE', { tipo })"
      @click="emit('pdf', seguro)"
    />
    <Button
      v-else-if="podeGuardar"
      slate
      faded
      size="lg"
      class="relative z-10 basis-full shrink-0 whitespace-nowrap sm:basis-auto"
      icon="i-lucide-paperclip"
      data-carteira="seguro-guardar-pdf"
      :label="tf('GUARDAR_PDF')"
      :aria-label="tf('GUARDAR_PDF_DE', { tipo })"
      @click="emit('guardar', seguro)"
    />
  </li>
</template>
