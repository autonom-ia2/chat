<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BOTAO_DISCRETO_DO_HEROI,
  BOTAO_PRINCIPAL_DO_HEROI,
} from '../../../../carteira/botoesDoHeroi';
import HeroiEscuro from '../../../comum/HeroiEscuro.vue';

// #2900 (E7.6) — o fim do "Trazer do Agger" não mente. A prova real: o
// gravador recusou os seguros e a tela disse "0 seguros chegaram", com "Ver
// os seguros", sem dizer o que houve.
//
// - Nenhum entrou e o gravador recusou algum: "Nenhum seguro entrou.", o
//   porquê de cada grupo com o que fazer, e "Buscar de novo" no lugar de "Ver
//   os seguros" (não há o que ver). Se todos batem com um seguro que já está
//   na carteira, buscar de novo não resolve: o botão é "Ver os seguros".
// - Entraram alguns e outros não: o título de sempre, e embaixo uma linha
//   calma "{n} não entraram" com o porquê.
// - Nada entrou porque tudo já estava na carteira, sem mudança: diz isso, e
//   "Ver os seguros" continua.
// O porquê vem do andamento (`naoEntraramPorque`, do que o gravador contou),
// sempre em frase de leigo, nunca o código.
const props = defineProps({
  // { seguros, pessoas, naoEntraram, naoEntraramPorque: { semDocumento,
  //   dadosErrados, outros } }
  andamento: { type: Object, default: () => ({}) },
  ocupado: { type: Boolean, default: false },
});
defineEmits(['buscar', 'ver', 'voltar']);

const { t } = useI18n();
// A frase de cada motivo do gravador, com as chaves escritas por inteiro.
const MOTIVOS = [
  [
    'semDocumento',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.PORQUE.SEM_DOCUMENTO',
        { count: quantos },
        quantos
      ),
  ],
  [
    'dadosErrados',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.PORQUE.DADOS_ERRADOS',
        { count: quantos },
        quantos
      ),
  ],
  [
    'conferir',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.PORQUE.CONFERIR',
        { count: quantos },
        quantos
      ),
  ],
  [
    'outros',
    quantos =>
      t(
        'RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.PORQUE.OUTROS',
        { count: quantos },
        quantos
      ),
  ],
];

const seguros = computed(() => props.andamento?.seguros ?? 0);
const pessoas = computed(() => props.andamento?.pessoas ?? 0);
const naoEntraram = computed(() => props.andamento?.naoEntraram ?? 0);
const nenhum = computed(() => !seguros.value && naoEntraram.value > 0);
const jaEstavam = computed(() => !seguros.value && !naoEntraram.value);

const porque = computed(() => {
  const motivos = props.andamento?.naoEntraramPorque ?? {};
  const comAlgum = MOTIVOS.filter(([motivo]) => motivos[motivo] > 0);
  return comAlgum.map(([motivo, fraseDoMotivo]) => ({
    motivo,
    frase: fraseDoMotivo(motivos[motivo]),
  }));
});
// O que bate com um seguro da carteira se confere na carteira: buscar de novo
// não resolve. Quando todos os que não entraram são assim, o botão principal
// volta a ser "Ver os seguros".
const soConferir = computed(
  () =>
    porque.value.length > 0 &&
    porque.value.every(item => item.motivo === 'conferir')
);
const buscarDeNovo = computed(() => nenhum.value && !soConferir.value);

const frase = computed(() => {
  if (nenhum.value) return t('RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.NENHUM');
  if (jaEstavam.value) {
    return t('RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.JA_ESTAVAM');
  }
  return [
    t(
      'RELACIONAMENTOS_CARTEIRA.TRAZER.PRONTO.CHEGARAM',
      { count: seguros.value },
      seguros.value
    ),
    t(
      'RELACIONAMENTOS_CARTEIRA.TRAZER.PRONTO.DE_PESSOAS',
      { count: pessoas.value },
      pessoas.value
    ),
  ].join(' ');
});

const linhaDosQueNaoEntraram = computed(() =>
  t(
    'RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.NAO_ENTRARAM',
    { count: naoEntraram.value },
    naoEntraram.value
  )
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <HeroiEscuro data-carteira="pronto-do-agger">
      <template #frase>
        <span data-carteira="frase-do-pronto" class="tabular-nums text-balance">
          {{ frase }}
        </span>
      </template>
      <template #apoio>
        <template v-if="nenhum">
          <span
            v-for="item in porque"
            :key="item.motivo"
            :data-motivo="item.motivo"
            class="block text-pretty"
          >
            {{ item.frase }}
          </span>
        </template>
        <template v-else>
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.APOIO') }}
        </template>
      </template>
      <template #acao>
        <Button
          v-if="buscarDeNovo"
          size="lg"
          data-carteira="buscar-de-novo-no-pronto"
          :class="BOTAO_PRINCIPAL_DO_HEROI"
          :is-loading="ocupado"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.BUSCAR_DE_NOVO')"
          @click="$emit('buscar')"
        />
        <Button
          v-else
          size="lg"
          data-carteira="ver-os-seguros"
          :class="BOTAO_PRINCIPAL_DO_HEROI"
          :label="t('RELACIONAMENTOS_CARTEIRA.TRAZER.PRONTO.VER')"
          @click="$emit('ver')"
        />
        <Button
          size="lg"
          data-carteira="voltar-ao-inicio"
          :class="BOTAO_DISCRETO_DO_HEROI"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.PRONTO.VOLTAR')"
          @click="$emit('voltar')"
        />
      </template>
    </HeroiEscuro>
    <section
      v-if="seguros && naoEntraram"
      data-carteira="nao-entraram"
      class="flex flex-col gap-2 px-4 py-3 rounded-2xl bg-n-alpha-1"
    >
      <p class="m-0 text-base font-medium tabular-nums text-n-slate-12">
        {{ linhaDosQueNaoEntraram }}
      </p>
      <p
        v-for="item in porque"
        :key="item.motivo"
        :data-motivo="item.motivo"
        class="m-0 text-sm text-n-slate-11 text-pretty"
      >
        {{ item.frase }}
      </p>
    </section>
  </div>
</template>
