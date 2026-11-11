<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../../comum/HeroiEscuro.vue';
import { COMO } from '../../../carteira/passosDeTrazerSeguros';

// #2897 — o fim de "trazer seguros": "168 seguros chegaram, de 120 pessoas.",
// a ação principal (Ver os seguros) e, na planilha e nos PDFs, a discreta de
// trazer mais. No Agger não há "trazer mais": ele busca sozinho todo dia.
const props = defineProps({
  como: { type: String, required: true },
  seguros: { type: Number, default: 0 },
  pessoas: { type: Number, default: 0 },
});
const emit = defineEmits(['ver', 'outra']);

const { t } = useI18n();
const tp = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.PRONTO.${chave}`, ...resto);

const OUTRA = { [COMO.PLANILHA]: 'OUTRA_LISTA', [COMO.PDFS]: 'MAIS_PDFS' };

const frase = computed(() =>
  [
    tp('CHEGARAM', { count: props.seguros }, props.seguros),
    tp('DE_PESSOAS', { count: props.pessoas }, props.pessoas),
  ].join(' ')
);
const doAgger = computed(() => props.como === COMO.AGGER);
</script>

<template>
  <div class="flex flex-col gap-4">
    <HeroiEscuro data-carteira="pronto">
      <template #frase>
        <span
          role="heading"
          aria-level="1"
          data-titulo-da-tela
          tabindex="-1"
          class="outline-none tabular-nums text-balance"
        >
          {{ frase }}
        </span>
      </template>
      <template v-if="doAgger" #apoio>{{ tp('AGGER_TODO_DIA') }}</template>
      <template #acao>
        <Button
          size="lg"
          data-carteira="ver-os-seguros"
          class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!outline-white"
          :label="tp('VER')"
          @click="emit('ver')"
        />
        <Button
          v-if="OUTRA[como]"
          size="lg"
          data-carteira="trazer-mais"
          class="!bg-white/10 !text-white/90 !outline-white/20 hover:enabled:!bg-white/20 focus-visible:!outline-white"
          :label="tp(OUTRA[como])"
          @click="emit('outra')"
        />
      </template>
    </HeroiEscuro>
    <p
      data-carteira="pronto-sossego"
      class="flex items-center gap-2 m-0 text-base text-n-slate-11"
    >
      <span class="i-lucide-undo-2 size-5 shrink-0" aria-hidden="true" />
      {{ tp('SOSSEGO') }}
    </p>
  </div>
</template>
