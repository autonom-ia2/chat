<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { trazerPdfsFonte } from '../../../../fonte/trazerPdfsFonte';
import {
  ETAPAS_DOS_PDFS,
  useLeituraDePdfs,
} from '../../../../carteira/useLeituraDePdfs';
import SoltarPdf from '../../SoltarPdf.vue';
import ProntoDeSeguros from '../ProntoDeSeguros.vue';
import EtapasDoTrazer from '../EtapasDoTrazer.vue';
import LinhaDeConfianca from '../LinhaDeConfianca.vue';
import VoltarDoTrazer from '../VoltarDoTrazer.vue';
import HistoricoDosPdfs from './HistoricoDosPdfs.vue';
import ItemDoPdf from './ItemDoPdf.vue';

// #2899 (E6.4) — "Trazer por PDFs": a pessoa solta os PDFs das apólices, cada
// um é lido em segundo plano, o Conferir mostra quantos seguros entram e
// quais PDFs pedem algo (o que falta, o contato achado sem certeza), e
// "Trazer" grava os prontos pela regra de sempre da carteira. Os lotes já
// enviados ficam embaixo, com "Desfazer". Só aparece na conta que lê PDF
// (pages/TrazerPage.vue).
//
// Sem botão desligado: sem seguro pronto, o "Trazer" não aparece e a frase do
// que fazer fica no lugar. Enquanto envia ou lê, a zona de soltar não aceita
// outro envio. Se o acompanhamento falha ou o lote para de andar, "Tentar de
// novo" retoma o mesmo lote. A cada etapa nova, o foco vai ao título.
// #3057 — no topo, a volta a "Como trazer" (VoltarDoTrazer) e as etapas da
// jornada (Enviar → Conferir → Pronto: enviar e ler são "Enviar"; conferir e
// trazer, "Conferir"). Embaixo do título, a linha de confiança.
const props = defineProps({
  fonte: { type: Object, default: () => trazerPdfsFonte() },
});

const { t } = useI18n();
const tp = (chave, valores, plural) =>
  plural === undefined
    ? t(`RELACIONAMENTOS_CARTEIRA.PDFS.${chave}`, valores)
    : t(`RELACIONAMENTOS_CARTEIRA.PDFS.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const historico = useTemplateRef('historico');
const titulo = useTemplateRef('titulo');

const leitura = useLeituraDePdfs(props.fonte, {
  aoMudarLote: id =>
    router.replace({ query: { ...route.query, lote: id ?? undefined } }),
});
const { etapa, lote, andamento, erro, ocupado, semAcompanhar, parado } =
  leitura;

const ETAPAS_DA_JORNADA = ['ENVIAR', 'CONFERIR', 'PRONTO'];
const NA_JORNADA = {
  [ETAPAS_DOS_PDFS.ENVIAR]: 0,
  [ETAPAS_DOS_PDFS.LENDO]: 0,
  [ETAPAS_DOS_PDFS.CONFERIR]: 1,
  [ETAPAS_DOS_PDFS.TRAZENDO]: 1,
  [ETAPAS_DOS_PDFS.PRONTO]: 2,
};
const naJornada = computed(() => NA_JORNADA[etapa.value] ?? 0);

const rotuloDeTrazer = seguros =>
  tp('CONFERIR.TRAZER', { count: seguros }, seguros);
const podeTentarDeNovo = computed(() => semAcompanhar.value || parado.value);

watch(etapa, async () => {
  await nextTick();
  titulo.value?.focus();
});

const itensDoConferir = computed(() => lote.value?.itens ?? []);
const chegaram = computed(() => ({
  seguros: andamento.value?.seguros ?? 0,
  pessoas: andamento.value?.pessoas ?? 0,
  pessoasNovas: andamento.value?.pessoasNovas ?? 0,
}));

const continuar = id => {
  router.replace({ query: { ...route.query, lote: id } });
  leitura.abrir(id);
};

const outra = () => {
  leitura.recomecar();
  historico.value?.carregar();
};

const verOsSeguros = () =>
  router.push({ name: 'relationships_home', query: { aba: 'seguros' } });

if (route.query.lote) leitura.abrir(Number(route.query.lote));
onBeforeUnmount(leitura.parar);
</script>

<template>
  <section
    data-relacionamentos="trazer-pdfs"
    class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1"
  >
    <div
      class="flex flex-col w-full max-w-3xl gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
    >
      <VoltarDoTrazer para="como" />
      <EtapasDoTrazer :etapas="ETAPAS_DA_JORNADA" :atual="naJornada" />
      <div class="flex flex-col gap-2">
        <h1
          ref="titulo"
          data-titulo-da-tela
          tabindex="-1"
          class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12 text-balance"
        >
          {{ tp('TITULO') }}
        </h1>
        <LinhaDeConfianca />
      </div>
      <p v-if="erro" role="alert" class="m-0 text-base text-n-ruby-11">
        {{ t(erro) }}
      </p>

      <template v-if="etapa === ETAPAS_DOS_PDFS.ENVIAR">
        <p
          v-if="ocupado"
          role="status"
          aria-busy="true"
          data-carteira="enviando-pdfs"
          class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ tp('ENVIANDO') }}
        </p>
        <SoltarPdf
          v-else
          varios
          :apoio="tp('APOIO')"
          @arquivos="leitura.enviar"
        />
        <HistoricoDosPdfs
          ref="historico"
          :fonte="fonte"
          @continuar="continuar"
        />
      </template>

      <template v-else-if="etapa === ETAPAS_DOS_PDFS.LENDO">
        <p
          role="status"
          aria-busy="true"
          data-carteira="lendo-pdfs"
          class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ tp('LENDO', { lidos: lote.lidos, total: lote.total }) }}
        </p>
        <Button
          v-if="semAcompanhar"
          size="lg"
          type="button"
          class="self-start"
          data-carteira="tentar-de-novo"
          :label="tp('TENTAR_DE_NOVO')"
          @click="leitura.tentarDeNovo"
        />
      </template>

      <template v-else-if="etapa === ETAPAS_DOS_PDFS.CONFERIR">
        <p data-carteira="numeros-dos-pdfs" class="m-0 text-lg text-n-slate-12">
          {{
            tp('CONFERIR.ENTRAM', {
              seguros: lote.seguros,
              pessoas: lote.pessoas,
            })
          }}
        </p>
        <ul
          class="flex flex-wrap gap-2 p-0 m-0 text-sm list-none text-n-slate-11"
        >
          <li v-if="lote.precisam">
            {{ tp('CONFERIR.PRECISAM', { n: lote.precisam }) }}
          </li>
          <li v-if="lote.recusados">
            {{ tp('CONFERIR.RECUSADOS', { n: lote.recusados }) }}
          </li>
          <li v-if="lote.naoDeuParaLer">
            {{ tp('CONFERIR.NAO_LEU', { n: lote.naoDeuParaLer }) }}
          </li>
          <li v-if="lote.fora">{{ tp('CONFERIR.FORA', { n: lote.fora }) }}</li>
        </ul>
        <ul class="flex flex-col gap-3 p-0 m-0 list-none">
          <ItemDoPdf
            v-for="item in itensDoConferir"
            :key="item.id"
            :item="item"
            :ocupado="ocupado"
            @mudar="pedido => leitura.mudarItem(item.id, pedido)"
          />
        </ul>
        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <Button
            slate
            faded
            size="lg"
            type="button"
            :label="tp('CONFERIR.OUTROS')"
            @click="outra"
          />
          <Button
            v-if="lote.seguros"
            size="lg"
            type="button"
            data-carteira="trazer-pdfs"
            :disabled="ocupado"
            :label="rotuloDeTrazer(lote.seguros)"
            @click="leitura.trazer"
          />
          <p
            v-else
            data-carteira="nada-para-trazer"
            class="m-0 text-base text-n-slate-11 sm:self-center sm:text-end"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.RECUSAS.NADA_PARA_TRAZER') }}
          </p>
        </div>
      </template>

      <template v-else-if="etapa === ETAPAS_DOS_PDFS.TRAZENDO">
        <p
          role="status"
          aria-busy="true"
          class="p-8 m-0 text-lg text-center border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ tp('TRAZENDO', { porcentagem: andamento?.porcentagem ?? 0 }) }}
        </p>
        <p
          v-if="parado && !semAcompanhar"
          data-carteira="trazendo-parado"
          class="m-0 text-base text-n-slate-11"
        >
          {{ tp('PARADO') }}
        </p>
        <Button
          v-if="podeTentarDeNovo"
          size="lg"
          type="button"
          class="self-start"
          data-carteira="tentar-de-novo"
          :label="tp('TENTAR_DE_NOVO')"
          @click="leitura.tentarDeNovo"
        />
      </template>

      <ProntoDeSeguros
        v-else
        :chegaram="chegaram"
        @ver="verOsSeguros"
        @outra="outra"
      />
    </div>
  </section>
</template>
