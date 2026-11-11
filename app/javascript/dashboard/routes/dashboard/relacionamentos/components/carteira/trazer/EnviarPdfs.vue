<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import SoltarArquivo from '../../trazer/SoltarArquivo.vue';
import { ACEITA_APOLICES } from '../../../carteira/arquivosDeApolice';
import { ERROS_DOS_PDFS } from '../../../carteira/useLeituraDePdfs';
import { larguraDaBarra } from '../../../trazer/larguraDaBarra';

// #2897 — "Traga os PDFs das suas apólices.": soltar vários de uma vez, ver
// quantos foram escolhidos e UM botão (Ler os PDFs). O botão fica sempre
// ligado: sem arquivo, o clique diz o que falta e leva o foco à área de soltar.
// Enquanto lê, a barra de andamento ("Lendo 12 de 40…").
const props = defineProps({
  arquivos: { type: Array, required: true },
  lendo: { type: Boolean, default: false },
  lidos: { type: Number, default: 0 },
  erro: { type: String, default: ERROS_DOS_PDFS.NENHUM },
  mostrarExemplo: { type: Boolean, default: false },
});
const emit = defineEmits(['arquivos', 'exemplo', 'outros', 'ler']);

const { t } = useI18n();
const tp = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.PDFS.${chave}`, ...resto);
const id = useId();
const idDoAviso = `${id}-aviso`;
const raiz = ref(null);
const falta = ref(false);
const nomesAbertos = ref(false);

const PORCENTAGEM_TOTAL = 100;
const total = computed(() => props.arquivos.length);
const porcentagem = computed(() =>
  total.value ? Math.floor((props.lidos / total.value) * PORCENTAGEM_TOTAL) : 0
);

// O que está errado com a escolha, embaixo da área de soltar: não escolheu
// nada, ou nada do que soltou é PDF de apólice.
const aviso = computed(() => {
  if (falta.value) {
    return { marca: 'falta-pdfs', texto: tp('FALTA_ESCOLHER') };
  }
  return props.erro === ERROS_DOS_PDFS.NENHUM_PDF
    ? { marca: 'pdfs-erro', texto: tp('NENHUM_PDF') }
    : null;
});

const ler = async () => {
  if (total.value) {
    emit('ler');
    return;
  }
  falta.value = true;
  await nextTick();
  raiz.value?.querySelector('[data-relacionamentos="soltar-arquivo"]')?.focus();
};

watch(total, () => {
  falta.value = false;
  nomesAbertos.value = false;
});
</script>

<template>
  <section ref="raiz" data-carteira="pdfs-enviar" class="flex flex-col gap-6">
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ tp('TITULO') }}
    </h1>

    <div
      v-if="lendo"
      data-carteira="pdfs-lendo"
      class="flex flex-col gap-4 p-8 border rounded-3xl border-n-weak bg-n-solid-1"
    >
      <p role="status" class="m-0 text-lg tabular-nums text-n-slate-12">
        {{ tp('LENDO', { lidos, total }) }}
      </p>
      <div
        role="progressbar"
        :aria-label="tp('LENDO_ROTULO')"
        aria-valuemin="0"
        :aria-valuemax="total"
        :aria-valuenow="lidos"
        class="h-3 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          class="h-full rounded-full bg-n-blue-11 dark:bg-n-blue-9"
          :class="larguraDaBarra(porcentagem)"
        />
      </div>
      <p class="m-0 text-base text-n-slate-11">{{ tp('LENDO_APOIO') }}</p>
    </div>

    <template v-else>
      <div v-if="erro === ERROS_DOS_PDFS.NAO_LEU" data-carteira="pdfs-erro">
        <ErroComTentarDeNovo :mensagem="tp('NAO_LEU')" @tentar="emit('ler')" />
      </div>

      <div
        v-if="total"
        data-carteira="pdfs-escolhidos"
        class="flex flex-col gap-3 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <p
          role="status"
          class="flex items-center gap-2 m-0 text-lg font-semibold tabular-nums text-n-slate-12"
        >
          <span
            class="i-lucide-files size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ tp('ESCOLHIDOS', { count: total }, total) }}
        </p>
        <button
          type="button"
          data-carteira="pdfs-ver-nomes"
          :aria-expanded="nomesAbertos"
          :aria-controls="`${id}-nomes`"
          class="self-start p-0 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="nomesAbertos = !nomesAbertos"
        >
          {{
            nomesAbertos
              ? tp('ESCONDER')
              : tp('VER_TODOS', { count: total }, total)
          }}
        </button>
        <ul
          v-if="nomesAbertos"
          :id="`${id}-nomes`"
          class="grid gap-x-6 gap-y-1 p-0 m-0 text-sm list-none sm:grid-cols-2 text-n-slate-11"
        >
          <li
            v-for="arquivo in arquivos"
            :key="arquivo.name"
            class="break-words"
          >
            {{ arquivo.name }}
          </li>
        </ul>
      </div>
      <div v-else data-carteira="pdfs-soltar" class="flex flex-col gap-3">
        <SoltarArquivo
          varios
          icone="i-lucide-file-text"
          :titulo="tp('SOLTAR')"
          :apoio="tp('APOIO')"
          :aceita="ACEITA_APOLICES"
          :invalido="Boolean(aviso)"
          :descrito-por="aviso ? idDoAviso : ''"
          @arquivos="emit('arquivos', $event)"
        />
        <p
          v-if="aviso"
          :id="idDoAviso"
          role="alert"
          :data-carteira="aviso.marca"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ aviso.texto }}
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <Button
          data-carteira="ler-pdfs"
          size="lg"
          :label="tp('LER')"
          @click="ler"
        />
        <Button
          v-if="total"
          slate
          faded
          size="lg"
          data-carteira="pdfs-escolher-outros"
          :label="tp('ESCOLHER_OUTROS')"
          @click="emit('outros')"
        />
        <Button
          v-else-if="mostrarExemplo"
          slate
          ghost
          size="lg"
          data-carteira="pdfs-usar-exemplo"
          :label="tp('USAR_EXEMPLO')"
          @click="emit('exemplo')"
        />
      </div>
    </template>
  </section>
</template>
