<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';

// #2900 (E7.6) — no Conferir do Agger, "12 não deram para trazer" com um
// "Ver por quê" ao lado, do mesmo jeito do "Ver quais seguradoras". Dentro,
// um grupo por motivo, com quantos e a frase do que fazer: falta dado do
// seguro no Agger, falta o CPF ou CNPJ, ou o Agger mandou de um jeito que não
// dá para ler. A busca calculada antes dos motivos não traz `porque`: aí fica
// só a linha, sem botão.
const props = defineProps({
  total: { type: Number, default: 0 },
  // { semDados, semDocumento, naoLeu } ou null
  porque: { type: Object, default: null },
});

const { t } = useI18n();
const id = useId();
const aberto = ref(false);
// A frase de cada motivo, com as chaves escritas por inteiro.
const MOTIVOS = [
  [
    'semDados',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.SEM_DADOS',
        { count: quantos },
        quantos
      ),
  ],
  [
    'semDocumento',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.SEM_DOCUMENTO',
        { count: quantos },
        quantos
      ),
  ],
  [
    'naoLeu',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.NAO_LEU',
        { count: quantos },
        quantos
      ),
  ],
];

const linha = computed(() =>
  t(
    'RELACIONAMENTOS_CARTEIRA.AGGER.CONFERIR.NAO_DEU',
    { count: props.total },
    props.total
  )
);

const motivos = computed(() => {
  const porque = props.porque ?? {};
  const comAlgum = MOTIVOS.filter(([motivo]) => porque[motivo] > 0);
  return comAlgum.map(([motivo, frase]) => ({
    motivo,
    quantos: t(
      'RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.QUANTOS',
      { count: porque[motivo] },
      porque[motivo]
    ),
    frase: frase(porque[motivo]),
  }));
});
</script>

<template>
  <section
    v-if="total"
    data-carteira="nao-deu-para-trazer"
    :aria-labelledby="`${id}-linha`"
    class="flex flex-col gap-3 px-4 py-3 rounded-2xl bg-n-alpha-1"
  >
    <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
      <p
        :id="`${id}-linha`"
        data-carteira="linha-do-nao-deu"
        class="flex-1 m-0 text-base text-n-slate-11 text-pretty"
      >
        {{ linha }}
      </p>
      <button
        v-if="motivos.length"
        type="button"
        data-carteira="ver-por-que"
        class="self-start px-4 text-sm font-medium border rounded-xl sm:self-center shrink-0 min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="aberto ? 'true' : 'false'"
        :aria-controls="`${id}-motivos`"
        @click="aberto = !aberto"
      >
        {{
          aberto
            ? t('RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.ESCONDER')
            : t('RELACIONAMENTOS_CARTEIRA.AGGER.POR_QUE.VER')
        }}
      </button>
    </div>
    <ul
      v-if="motivos.length"
      v-show="aberto"
      :id="`${id}-motivos`"
      data-carteira="motivos-do-nao-deu"
      class="flex flex-col gap-4 p-0 pt-3 m-0 list-none border-t border-n-weak"
    >
      <li
        v-for="item in motivos"
        :key="item.motivo"
        :data-motivo="item.motivo"
        class="flex flex-col gap-1"
      >
        <span class="text-base font-medium tabular-nums text-n-slate-12">
          {{ item.quantos }}
        </span>
        <span class="text-sm text-n-slate-11 text-pretty">
          {{ item.frase }}
        </span>
      </li>
    </ul>
  </section>
</template>
