<script setup>
import { computed, nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import SoltarArquivo from '../trazer/SoltarArquivo.vue';
import { ETAPAS_DO_PDF, useAnexarPdf } from '../../carteira/useAnexarPdf';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import OQueMudou from './OQueMudou.vue';

// #2897 — anexar o PDF de um seguro e ver, lado a lado, o que o PDF diz de
// diferente. Três momentos no mesmo diálogo: soltar o arquivo, lendo e "O que
// mudou". A ação principal é "Usar o que está no PDF"; "Manter como está"
// guarda o PDF sem mudar os dados. No renovado, o PDF é a apólice nova.
const props = defineProps({
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['guardado']);

const ARQUIVO_DE_EXEMPLO = { name: 'apolice-de-exemplo.pdf' };
const SO_PDF = '.pdf,application/pdf';

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PDF.${chave}`, valores);
const textos = useTextosDoSeguro();
const dialogo = useTemplateRef('dialogo');
const corpo = useTemplateRef('corpo');
const pdf = useAnexarPdf(props.fonte);

const titulo = computed(() => {
  if (!pdf.seguro.value) return '';
  return pdf.apoliceNova.value
    ? tp('TITULO_APOLICE_NOVA')
    : tp('TITULO', { tipo: textos.tipo(pdf.seguro.value) });
});
const temMudanca = computed(() => pdf.mudancas.value.length > 0);

// Ao chegar no "O que mudou", o foco vai ao título dele: o leitor de tela diz
// onde a pessoa está.
const ler = async arquivo => {
  await pdf.ler(arquivo);
  await nextTick();
  corpo.value?.querySelector('[data-foco-do-passo]')?.focus();
};

const guardar = async usarPdf => {
  const guardado = await pdf.guardar({ usarPdf });
  if (!guardado) return;
  emit('guardado', { seguro: guardado, apoliceNova: pdf.apoliceNova.value });
  dialogo.value?.close();
};

defineExpose({
  abrir: seguro => {
    pdf.comecar(seguro);
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog ref="dialogo" width="lg" @confirm="guardar(true)">
    <div ref="corpo" data-carteira="anexar-pdf" class="flex flex-col gap-5">
      <TituloDoDialogo :titulo="titulo" />

      <p
        v-if="pdf.etapa.value === ETAPAS_DO_PDF.LENDO"
        data-carteira="lendo-pdf"
        role="status"
        aria-busy="true"
        class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        {{ tp('LENDO') }}
      </p>

      <template v-else-if="pdf.etapa.value === ETAPAS_DO_PDF.SOLTAR">
        <div data-carteira="soltar-pdf">
          <SoltarArquivo
            icone="i-lucide-file-text"
            :titulo="tp('SOLTAR')"
            :aceita="SO_PDF"
            @arquivo="ler"
          />
        </div>
        <p
          v-if="pdf.erro.value"
          role="alert"
          data-carteira="erro-pdf"
          :data-erro="pdf.erro.value"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ tp(pdf.erro.value) }}
        </p>
        <button
          v-if="fonte.usaDemo"
          type="button"
          data-carteira="usar-exemplo"
          class="self-start p-0 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="ler(ARQUIVO_DE_EXEMPLO)"
        >
          {{ tp('USAR_EXEMPLO') }}
        </button>
      </template>

      <template v-else>
        <h4
          data-foco-do-passo
          tabindex="-1"
          class="m-0 text-base font-semibold outline-none text-n-slate-12"
        >
          {{ temMudanca ? tp('O_QUE_MUDOU') : tp('CONFERE') }}
        </h4>
        <OQueMudou
          v-if="temMudanca"
          :linhas="pdf.mudancas.value"
          :escolhidos="pdf.escolhidos.value"
          @usar-do-pdf="pdf.usarDoPdf"
        />
        <p
          v-if="pdf.erro.value"
          role="alert"
          data-carteira="erro-pdf"
          :data-erro="pdf.erro.value"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ tp(pdf.erro.value) }}
        </p>
      </template>
    </div>
    <template #footer>
      <div
        class="flex flex-col-reverse w-full gap-3 sm:flex-row sm:justify-end"
      >
        <Button
          v-if="pdf.etapa.value !== ETAPAS_DO_PDF.MUDOU"
          slate
          faded
          size="lg"
          type="button"
          class="w-full sm:w-auto"
          :label="tp('FECHAR')"
          @click="dialogo?.close()"
        />
        <template v-else>
          <Button
            v-if="temMudanca"
            slate
            faded
            size="lg"
            type="button"
            class="w-full sm:w-auto"
            data-carteira="manter"
            :disabled="pdf.guardando.value"
            :label="tp('MANTER')"
            @click="guardar(false)"
          />
          <Button
            size="lg"
            type="submit"
            class="w-full sm:w-auto"
            data-carteira="usar-pdf"
            :is-loading="pdf.guardando.value"
            :label="tp(temMudanca ? 'USAR_O_QUE_ESTA_NO_PDF' : 'GUARDAR')"
          />
        </template>
      </div>
    </template>
  </Dialog>
</template>
