<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { diasParaTerminar, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { tomDoSelo } from '../../carteira/tomDoSelo';
import { ONDE, useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SeloDoSeguro from './SeloDoSeguro.vue';

// #2897 — um seguro no painel da conversa: tipo, selo, seguradora e quando
// vence. É a linha da ficha, mais curta: sem ícone e sem o número da apólice,
// que ficam para a gaveta. Clicar na linha abre a gaveta do seguro (o botão do
// tipo estica a área de clique); "Ver PDF" fica por cima. O painel é estreito:
// quando "Ver PDF" não cabe ao lado sem espremer o texto, ele desce inteiro
// para a linha de baixo.
// A frase de quando vence leva a cor do selo quando ele pede atenção: âmbar no
// ativo que vence em até 30 dias, vermelho no vencido. A regra é a mesma do
// selo (carteira/tomDoSelo.js).
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'pdf']);

const COR_DE_QUEM_PEDE_ATENCAO = {
  ambar: 'text-n-amber-11',
  vermelho: 'text-n-ruby-11',
};

const { t } = useI18n();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.FICHA.${chave}`, valores);
const textos = useTextosDoSeguro();

const tipo = computed(() => textos.tipo(props.seguro));
const tom = computed(() =>
  tomDoSelo(
    seloDoSeguro(props.seguro, props.agora),
    diasParaTerminar(props.seguro, props.agora)
  )
);
const corDoQuando = computed(
  () => COR_DE_QUEM_PEDE_ATENCAO[tom.value] ?? 'text-n-slate-11'
);
</script>

<template>
  <li
    data-carteira="painel-seguro"
    :data-apolice="seguro.id"
    :data-tom="tom"
    class="relative flex flex-wrap items-center min-w-0 p-3 transition-colors border gap-x-3 gap-y-1 rounded-xl border-n-weak hover:border-n-blue-6 hover:bg-n-alpha-1"
  >
    <div class="flex flex-col flex-1 gap-0.5 min-w-[12.5rem]">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <button
          type="button"
          :aria-label="tf('ABRIR', { tipo })"
          class="p-0 text-sm font-semibold break-words bg-transparent border-0 text-start text-n-slate-12 after:absolute after:inset-0 after:rounded-xl focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:outline-n-brand"
          @click="emit('abrir', seguro)"
        >
          {{ tipo }}
        </button>
        <SeloDoSeguro :seguro="seguro" :agora="agora" />
      </div>
      <p class="m-0 text-sm break-words text-n-slate-11">
        {{ seguro.seguradora }}
      </p>
      <p
        data-carteira="painel-quando"
        class="m-0 text-sm break-words"
        :class="corDoQuando"
      >
        {{ textos.quando(seguro, agora, ONDE.FICHA) }}
      </p>
    </div>
    <Button
      v-if="seguro.temPdf"
      slate
      faded
      size="sm"
      class="relative z-10 shrink-0 min-h-11"
      icon="i-lucide-file-text"
      data-carteira="painel-pdf"
      :label="tf('VER_PDF')"
      :aria-label="tf('VER_PDF_DE', { tipo })"
      @click="emit('pdf', seguro)"
    />
  </li>
</template>
