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
// A prévia diz só as partes que não são zero, cada uma no singular ou plural.
const props = defineProps({
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['continuar']);

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU';
const CONTINUA = ['lendo', 'parou', 'lida', 'trazendo'];
const BASE = 'RELACIONAMENTOS_CARTEIRA.AGGER.HISTORICO';
const PARTES_DA_PREVIA = [
  ['SAEM', 'saem'],
  ['VOLTAM', 'voltam'],
  ['FICAM', 'ficam'],
  ['PESSOAS_SAEM', 'pessoasSaem'],
  ['PESSOAS_FICAM', 'pessoasFicam'],
];

const { t, locale } = useI18n();
const th = (chave, valores, plural) =>
  plural === undefined
    ? t(`${BASE}.${chave}`, valores)
    : t(`${BASE}.${chave}`, valores, plural);
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
  const comNumero = PARTES_DA_PREVIA.filter(([, campo]) => previa.value[campo]);
  const partes = comNumero.map(([chave, campo]) => {
    const count = previa.value[campo];
    return th(`PREVIA.AVISO.${chave}`, { count }, count);
  });
  return partes.length ? partes.join(' ') : th('PREVIA.AVISO.NADA');
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
  th(diaria ? 'LINHA_DIARIA' : 'LINHA', { count: seguros }, seguros);

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
      {{ th('TITULO') }}
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
              th('QUANDO', {
                quando: quando(busca.quando),
                situacao: th(`SITUACAO.${busca.situacao.toUpperCase()}`),
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
          {{ th('CONTINUAR') }}
        </button>
        <button
          v-else-if="busca.podeDesfazer"
          type="button"
          data-carteira="desfazer-busca"
          class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="pedirDesfazer(busca)"
        >
          {{ th('DESFAZER') }}
        </button>
      </li>
    </ul>
    <DialogoDeConfirmacao
      ref="dialogo"
      marca="desfazer-busca"
      :titulo="th('PREVIA.TITULO')"
      :aviso="avisoDaPrevia"
      :confirmar="th('PREVIA.CONFIRMAR')"
      :voltar="th('PREVIA.VOLTAR')"
      :ocupado="ocupado"
      @confirmar="desfazer"
      @fechou="escolhida = null"
    />
  </section>
</template>
