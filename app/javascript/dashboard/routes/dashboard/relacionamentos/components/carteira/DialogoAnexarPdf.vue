<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { ETAPAS, useAnexarPdf } from '../../carteira/useAnexarPdf';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import DialogoDeConfirmacao from './DialogoDeConfirmacao.vue';
import OQueMudou from './OQueMudou.vue';
import SoltarPdf from './SoltarPdf.vue';

// #2897 — guardar o PDF de um seguro. Sem PDF antes é um passo só: a pessoa
// solta (ou escolhe) o arquivo e ele já é guardado. Um PDF por seguro: quando
// já há um, escolher o arquivo abre a pergunta "Trocar o PDF deste seguro?",
// porque o que está guardado sai e não volta. Nada é lido do PDF. Arquivo
// grande demais nem é enviado; se o servidor recusa (não é PDF), a frase
// aparece aqui e a pessoa escolhe outro. Quem abriu recebe `guardado` com o
// seguro como ficou e se ele já tinha PDF antes (`tinhaPdf`: sem isso não há o
// que desfazer).
//
// #2899 (E6.2) — na conta com a leitura de PDF liberada (o resumo da carteira
// diz `leituraDePdf`), o PDF é lido antes de guardar e a pessoa vê o que mudou
// (OQueMudou.vue): "Guardar" leva os campos escolhidos, "Manter como está"
// guarda só o PDF. Sem a leitura, nada aqui fala de leitura (decisão D4).
const props = defineProps({
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['guardado']);

const ARQUIVO_DE_EXEMPLO = { name: 'apolice-de-exemplo.pdf' };

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PDF.${chave}`, valores);
const textos = useTextosDoSeguro();
const dialogo = useTemplateRef('dialogo');
const dialogoDeTroca = useTemplateRef('dialogoDeTroca');
const pdf = useAnexarPdf(props.fonte);
// O arquivo escolhido para entrar no lugar do que está guardado, à espera do
// "Trocar o PDF".
const paraTrocar = ref(null);
// A conta lê PDF? Só com `leituraDePdf: true` no resumo; na dúvida, não.
const lePdf = ref(false);

const perguntarSeLe = async () => {
  try {
    lePdf.value = (await props.fonte.resumo())?.leituraDePdf === true;
  } catch {
    lePdf.value = false;
  }
};

const tinhaPdf = computed(() => Boolean(pdf.seguro.value?.temPdf));
const titulo = computed(() =>
  pdf.seguro.value
    ? tp(tinhaPdf.value ? 'TITULO_OUTRO' : 'TITULO', {
        tipo: textos.tipo(pdf.seguro.value),
      })
    : ''
);

const terminar = guardado => {
  if (!guardado) return;
  emit('guardado', { seguro: guardado, tinhaPdf: tinhaPdf.value });
  dialogo.value?.close();
};

const guardar = async arquivo => {
  const comLeitura = lePdf.value;
  if (paraTrocar.value) dialogoDeTroca.value?.fechar();
  terminar(await (comLeitura ? pdf.ler(arquivo) : pdf.guardar(arquivo)));
};

const guardarSemLer = async () =>
  terminar(await pdf.guardar(pdf.naoLido.value));

const guardarLido = async usar => terminar(await pdf.guardarLido(usar));

const aoEscolher = arquivo => {
  if (!tinhaPdf.value) {
    guardar(arquivo);
    return;
  }
  // O arquivo que não cabe já diz por quê: não chega a perguntar pela troca.
  if (!pdf.conferir(arquivo)) return;
  paraTrocar.value = arquivo;
  dialogoDeTroca.value?.abrir();
};

defineExpose({
  abrir: seguro => {
    pdf.comecar(seguro);
    paraTrocar.value = null;
    lePdf.value = false;
    perguntarSeLe();
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog ref="dialogo" width="lg">
    <div data-carteira="guardar-pdf" class="flex flex-col gap-5">
      <TituloDoDialogo :titulo="titulo" />
      <p
        v-if="pdf.guardando.value || pdf.etapa.value === ETAPAS.LENDO"
        data-carteira="guardando-pdf"
        role="status"
        aria-busy="true"
        class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        {{ tp(pdf.guardando.value ? 'GUARDANDO' : 'LENDO') }}
      </p>
      <template v-else-if="pdf.etapa.value === ETAPAS.MUDOU">
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ tp('MUDOU.TITULO') }}
        </h3>
        <OQueMudou
          :mudancas="pdf.mudancas.value"
          :escolhidos="pdf.escolhidos.value"
          :outra-apolice="pdf.outraApolice.value"
          @trocar="pdf.trocarEscolha"
        />
        <p
          v-if="pdf.erro.value"
          role="alert"
          data-carteira="erro-pdf"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ t(pdf.erro.value) }}
        </p>
        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <Button
            slate
            faded
            size="lg"
            type="button"
            data-carteira="manter-como-esta"
            :label="tp('MUDOU.MANTER')"
            @click="guardarLido([])"
          />
          <Button
            size="lg"
            type="button"
            data-carteira="guardar-o-que-mudou"
            :label="tp('MUDOU.GUARDAR')"
            @click="guardarLido(pdf.escolhidos.value)"
          />
        </div>
      </template>
      <template v-else>
        <SoltarPdf
          :apoio="tp(tinhaPdf ? 'APOIO_OUTRO' : lePdf ? 'APOIO_LER' : 'APOIO')"
          @arquivo="aoEscolher"
        />
        <p
          v-if="pdf.erro.value"
          role="alert"
          data-carteira="erro-pdf"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ t(pdf.erro.value) }}
        </p>
        <button
          v-if="pdf.naoLido.value"
          type="button"
          data-carteira="guardar-sem-ler"
          class="self-start p-0 text-base font-medium underline bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="guardarSemLer"
        >
          {{ tp('GUARDAR_SEM_LER') }}
        </button>
        <button
          v-if="fonte.usaDemo"
          type="button"
          data-carteira="usar-exemplo"
          class="self-start p-0 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="aoEscolher(ARQUIVO_DE_EXEMPLO)"
        >
          {{ tp('USAR_EXEMPLO') }}
        </button>
      </template>
    </div>
    <template #footer>
      <div class="flex w-full sm:justify-end">
        <Button
          slate
          faded
          size="lg"
          type="button"
          class="w-full sm:w-auto"
          :label="tp('FECHAR')"
          @click="dialogo?.close()"
        />
      </div>
    </template>
  </Dialog>
  <DialogoDeConfirmacao
    ref="dialogoDeTroca"
    marca="trocar-pdf"
    :titulo="tp('TROCAR.TITULO')"
    :aviso="tp('TROCAR.AVISO')"
    :confirmar="tp('TROCAR.CONFIRMAR')"
    :voltar="tp('TROCAR.VOLTAR')"
    :ocupado="pdf.guardando.value"
    @confirmar="guardar(paraTrocar)"
    @fechou="paraTrocar = null"
  />
</template>
