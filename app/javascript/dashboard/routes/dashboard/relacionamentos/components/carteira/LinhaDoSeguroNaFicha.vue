<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { SELOS, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { iconeDoTipo } from '../../carteira/tiposDeSeguro';
import { ONDE, useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SelosDoSeguro from './SelosDoSeguro.vue';

// #2897 — um seguro no bloco Seguros da ficha: tipo, selo, seguradora e número,
// quando vence e o botão do PDF (ou "Anexar PDF", quando falta). Clicar na
// linha abre a gaveta do seguro: o botão do tipo estica a área de clique; o
// botão do PDF fica por cima. `compacta` é a linha do painel da conversa: tipo,
// selo e quando vence. O seguro de outra corretora só informa (não abre gaveta).
// Em tela estreita "Anexar PDF" desce para a linha de baixo, inteiro: ao lado
// ele espremeria o texto.
const props = defineProps({
  seguro: { type: Object, required: true },
  compacta: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrir', 'pdf', 'anexar']);

const DIAS_DO_LEMBRETE = 60;

const { t } = useI18n();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.FICHA.${chave}`, valores);
const textos = useTextosDoSeguro();

const tipo = computed(() => textos.tipo(props.seguro));
const selo = computed(() => seloDoSeguro(props.seguro, props.agora));
const deFora = computed(() => selo.value === SELOS.EM_OUTRA_CORRETORA);
const cancelado = computed(() => selo.value === SELOS.CANCELADO);
const marca = nome => (props.compacta ? `painel-${nome}` : `seguro-${nome}`);

const linhas = computed(() => {
  const { seguro, agora, compacta } = props;
  // No painel o selo já diz "Em outra corretora": a linha diz quando termina.
  if (compacta && deFora.value) {
    return [
      t('RELACIONAMENTOS_CARTEIRA.PAINEL.DE_FORA_TERMINA', {
        data: textos.dataInteira(seguro.termina),
      }),
    ];
  }
  if (compacta) return [textos.quando(seguro, agora, ONDE.PAINEL)];
  if (deFora.value) {
    return [
      [seguro.seguradora, textos.quando(seguro, agora, ONDE.LISTA)].join(' · '),
      tf('LEMBRETE', {
        data: textos.diaMes(seguro.lembreteEm, agora),
        dias: DIAS_DO_LEMBRETE,
      }),
    ];
  }
  return [
    tf('SEGURADORA_E_NUMERO', {
      seguradora: seguro.seguradora,
      numero: seguro.numero,
    }),
    textos.quando(seguro, agora, ONDE.FICHA),
  ];
});
</script>

<template>
  <li
    :data-carteira="compacta ? 'painel-seguro' : 'seguro'"
    :data-apolice="seguro.id"
    class="relative flex flex-wrap items-center min-w-0 gap-3 transition-colors border rounded-xl border-n-weak"
    :class="[
      compacta ? 'p-2 ps-3' : 'p-3 sm:p-4',
      deFora ? '' : 'hover:border-n-blue-6 hover:bg-n-alpha-1',
    ]"
  >
    <span
      v-if="!compacta"
      class="flex items-center justify-center rounded-full size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
      aria-hidden="true"
    >
      <span class="size-5" :class="iconeDoTipo(seguro.tipo)" />
    </span>
    <div
      class="flex flex-col flex-1 min-w-0 gap-0.5"
      :class="{ 'text-n-slate-10': cancelado }"
    >
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span
          v-if="deFora"
          class="text-base font-semibold break-words text-n-slate-12"
        >
          {{ tipo }}
        </span>
        <button
          v-else
          type="button"
          :aria-label="tf('ABRIR', { tipo })"
          class="p-0 text-base font-semibold break-words bg-transparent border-0 text-start after:absolute after:inset-0 after:rounded-xl focus-visible:outline-none focus-visible:after:outline focus-visible:after:outline-2 focus-visible:after:outline-n-brand"
          :class="cancelado ? 'text-n-slate-11' : 'text-n-slate-12'"
          @click="emit('abrir', seguro)"
        >
          {{ tipo }}
        </button>
        <SelosDoSeguro :seguro="seguro" :agora="agora" />
      </div>
      <p
        v-for="(linha, indice) in linhas"
        :key="indice"
        class="m-0 text-sm break-words"
        :class="cancelado ? 'text-n-slate-10' : 'text-n-slate-11'"
      >
        {{ linha }}
      </p>
    </div>
    <template v-if="!deFora">
      <Button
        v-if="seguro.temPdf"
        slate
        faded
        size="lg"
        class="relative z-10 shrink-0"
        icon="i-lucide-file-text"
        :data-carteira="marca('pdf')"
        :label="tf('PDF')"
        :aria-label="tf('VER_PDF_DE', { tipo })"
        @click="emit('pdf', seguro)"
      />
      <Button
        v-else-if="!compacta"
        slate
        faded
        size="lg"
        class="relative z-10 basis-full shrink-0 whitespace-nowrap sm:basis-auto"
        icon="i-lucide-paperclip"
        data-carteira="seguro-anexar"
        :label="tf('ANEXAR_PDF')"
        :aria-label="tf('ANEXAR_PDF_DE', { tipo })"
        @click="emit('anexar', seguro)"
      />
    </template>
  </li>
</template>
