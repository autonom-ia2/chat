<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  chaveDaRecusaDoAgger,
  codigoDaRecusa,
} from '../../../../carteira/recusas';
import DialogoDeConfirmacao from '../../DialogoDeConfirmacao.vue';

// #2900 (E7.3) — as buscas no Agger já feitas, a mais nova primeiro: a
// primeira (que a pessoa trouxe do Conferir) e as de todo dia, que entram
// sozinhas. A que ainda está buscando ou no Conferir tem "Continuar"; a
// trazida, dentro da guarda, tem "Desfazer", que antes mostra o que sai e o que
// fica (a mesma prévia dos PDFs: só sai o que veio na busca e ninguém mexeu).
const props = defineProps({
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['continuar']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU';
const CONTINUA = ['lendo', 'parou', 'lida', 'trazendo'];

const { t, locale } = useI18n();
// Cada parte da prévia do Desfazer, no singular ou no plural; só entra a que
// não é zero.
const PARTES_DA_PREVIA = {
  saem: count =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.SAEM',
      { count },
      count
    ),
  voltam: count =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.VOLTAM',
      { count },
      count
    ),
  ficam: count =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.FICAM',
      { count },
      count
    ),
  pessoasSaem: count =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.PESSOAS_SAEM',
      { count },
      count
    ),
  pessoasFicam: count =>
    t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.PESSOAS_FICAM',
      { count },
      count
    ),
};
const SITUACOES = {
  lendo: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.LENDO'),
  parou: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.PAROU'),
  lida: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.LIDA'),
  trazendo: () =>
    t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.TRAZENDO'),
  trazida: () => t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.TRAZIDA'),
  desfazendo: () =>
    t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.DESFAZENDO'),
  desfeita: () =>
    t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.SITUACAO.DESFEITA'),
};
const linhaDiaria = count =>
  t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.LINHA_DIARIA', { count }, count);
const linhaDaBusca = count =>
  t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.LINHA', { count }, count);
const textosDaPrevia = computed(() => ({
  titulo: t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.TITULO'),
  confirmar: t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.CONFIRMAR'),
  voltar: t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.VOLTAR'),
}));
const buscas = ref([]);
const erro = ref('');
const ocupado = ref(false);
const previa = ref(null);
const escolhida = ref(null);
const dialogo = useTemplateRef('dialogo');

const quando = texto =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(texto));

const falhou = falha => {
  erro.value = chaveDaRecusaDoAgger(codigoDaRecusa(falha), NAO_DEU);
};

const avisoDaPrevia = computed(() => {
  if (!previa.value) return '';
  const campos = Object.keys(PARTES_DA_PREVIA);
  const comNumero = campos.filter(campo => previa.value[campo]);
  const partes = comNumero.map(campo =>
    PARTES_DA_PREVIA[campo](previa.value[campo])
  );
  return partes.length
    ? partes.join(' ')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.PREVIA.AVISO.NADA');
});

const carregar = async () => {
  erro.value = '';
  try {
    buscas.value = await props.fonte.historico();
  } catch (falha) {
    falhou(falha);
  }
};

const pedirDesfazer = async busca => {
  erro.value = '';
  try {
    previa.value = await props.fonte.previaDoDesfazer(busca.id);
    escolhida.value = busca;
    dialogo.value?.abrir();
  } catch (falha) {
    falhou(falha);
  }
};

const desfazer = async () => {
  ocupado.value = true;
  try {
    await props.fonte.desfazer(escolhida.value.id);
    dialogo.value?.fechar();
    await carregar();
  } catch (falha) {
    falhou(falha);
    dialogo.value?.fechar();
  } finally {
    ocupado.value = false;
  }
};

const linha = ({ diaria, seguros }) =>
  diaria ? linhaDiaria(seguros) : linhaDaBusca(seguros);

onMounted(carregar);
defineExpose({ carregar });
</script>

<template>
  <section
    data-carteira="historico-das-buscas"
    class="flex flex-col gap-3"
    :class="{ hidden: !buscas.length && !erro }"
  >
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.TITULO') }}
    </h2>
    <template v-if="erro">
      <p role="alert" class="m-0 text-base text-n-ruby-11">{{ t(erro) }}</p>
      <button
        type="button"
        data-carteira="tentar-historico"
        class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="carregar"
      >
        {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.TENTAR_DE_NOVO') }}
      </button>
    </template>
    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="busca in buscas"
        :key="busca.id"
        :data-busca="busca.id"
        class="flex flex-col gap-2 p-4 border sm:flex-row sm:items-center sm:justify-between rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-col gap-1">
          <span class="text-base font-medium text-n-slate-12">
            {{ linha(busca) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.QUANDO', {
                quando: quando(busca.quando),
                situacao: SITUACOES[busca.situacao](),
              })
            }}
          </span>
        </div>
        <button
          v-if="CONTINUA.includes(busca.situacao)"
          type="button"
          data-carteira="continuar-busca"
          class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('continuar', busca.id)"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.CONTINUAR') }}
        </button>
        <button
          v-else-if="busca.podeDesfazer"
          type="button"
          data-carteira="desfazer-busca"
          class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="pedirDesfazer(busca)"
        >
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO.DESFAZER') }}
        </button>
      </li>
    </ul>
    <DialogoDeConfirmacao
      ref="dialogo"
      marca="desfazer-busca"
      :titulo="textosDaPrevia.titulo"
      :aviso="avisoDaPrevia"
      :confirmar="textosDaPrevia.confirmar"
      :voltar="textosDaPrevia.voltar"
      :ocupado="ocupado"
      @confirmar="desfazer"
      @fechou="escolhida = null"
    />
  </section>
</template>
