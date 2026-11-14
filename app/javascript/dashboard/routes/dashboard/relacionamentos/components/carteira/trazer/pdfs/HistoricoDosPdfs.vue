<script setup>
import { onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { chaveDaRecusa, codigoDaRecusa } from '../../../../carteira/recusas';
import DialogoDeConfirmacao from '../../DialogoDeConfirmacao.vue';

// #2899 (E6.4) — os lotes de PDFs já enviados, o mais novo primeiro. O lote
// que ainda está no Conferir tem "Continuar"; o trazido, dentro da guarda,
// tem "Desfazer", que antes mostra o que sai e o que fica (a prévia diz o
// mesmo que o Desfazer vai fazer: só sai o que veio no lote e ninguém mexeu).
// O lote que ficou em "entrando" tem "Tentar de novo": pede o Trazer outra vez
// (o servidor é idempotente e só põe a gravação na fila de novo se ela parou) e
// leva a pessoa a acompanhar.
const props = defineProps({
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['continuar']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.PDFS.NAO_DEU';
const NO_CONFERIR = ['lendo', 'lida'];
const ENTRANDO = 'trazendo';

const { t, locale } = useI18n();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.PDFS.${chave}`);
const th = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PDFS.HISTORICO.${chave}`, valores);
const lotes = ref([]);
const erro = ref('');
const ocupado = ref(false);
const previa = ref(null);
const escolhido = ref(null);
const dialogo = useTemplateRef('dialogo');

const quando = texto =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(texto));

const carregar = async () => {
  try {
    lotes.value = await props.fonte.historico();
  } catch (falha) {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
  }
};

const pedirDesfazer = async lote => {
  erro.value = '';
  try {
    previa.value = await props.fonte.previaDoDesfazer(lote.id);
    escolhido.value = lote;
    dialogo.value?.abrir();
  } catch (falha) {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
  }
};

const tentarDeNovo = async lote => {
  erro.value = '';
  try {
    await props.fonte.trazer(lote.id);
    emit('continuar', lote.id);
  } catch (falha) {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
  }
};

const desfazer = async () => {
  ocupado.value = true;
  try {
    await props.fonte.desfazer(escolhido.value.id);
    dialogo.value?.fechar();
    await carregar();
  } catch (falha) {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
    dialogo.value?.fechar();
  } finally {
    ocupado.value = false;
  }
};

onMounted(carregar);
defineExpose({ carregar });
</script>

<template>
  <section
    data-carteira="historico-dos-pdfs"
    class="flex flex-col gap-3"
    :class="{ hidden: !lotes.length && !erro }"
  >
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ th('TITULO') }}
    </h2>
    <p v-if="erro" role="alert" class="m-0 text-base text-n-ruby-11">
      {{ t(erro) }}
    </p>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="lote in lotes"
        :key="lote.id"
        :data-lote="lote.id"
        class="flex flex-col gap-2 p-4 border sm:flex-row sm:items-center sm:justify-between rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-col gap-1">
          <span class="text-base font-medium text-n-slate-12">
            {{ th('LINHA', { pdfs: lote.pdfs, seguros: lote.seguros }) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              th('QUANDO', {
                quando: quando(lote.quando),
                situacao: th(`SITUACAO.${lote.situacao.toUpperCase()}`),
              })
            }}
          </span>
        </div>
        <button
          v-if="NO_CONFERIR.includes(lote.situacao)"
          type="button"
          data-carteira="continuar-lote"
          class="self-start px-3 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('continuar', lote.id)"
        >
          {{ th('CONTINUAR') }}
        </button>
        <button
          v-else-if="lote.situacao === ENTRANDO"
          type="button"
          data-carteira="tentar-lote-de-novo"
          class="self-start px-3 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="tentarDeNovo(lote)"
        >
          {{ tp('TENTAR_DE_NOVO') }}
        </button>
        <button
          v-else-if="lote.podeDesfazer"
          type="button"
          data-carteira="desfazer-lote"
          class="self-start px-3 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="pedirDesfazer(lote)"
        >
          {{ th('DESFAZER') }}
        </button>
      </li>
    </ul>
    <DialogoDeConfirmacao
      ref="dialogo"
      marca="desfazer-pdfs"
      :titulo="th('PREVIA.TITULO')"
      :aviso="previa ? th('PREVIA.AVISO', previa) : ''"
      :confirmar="th('PREVIA.CONFIRMAR')"
      :voltar="th('PREVIA.VOLTAR')"
      :ocupado="ocupado"
      @confirmar="desfazer"
      @fechou="escolhido = null"
    />
  </section>
</template>
