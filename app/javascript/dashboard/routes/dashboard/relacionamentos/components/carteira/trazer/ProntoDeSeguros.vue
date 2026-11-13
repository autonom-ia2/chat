<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../../comum/HeroiEscuro.vue';

// #2897 — o fim, na lista que trouxe seguros: "164 seguros chegaram, de 118
// pessoas.", quantas dessas pessoas são novas, a ação principal (Ver os
// seguros) e a discreta (Trazer outra lista). Os números são os que o servidor
// conta depois de trazer.
const props = defineProps({
  // `{ seguros, pessoas, pessoasNovas }`
  chegaram: { type: Object, required: true },
});
const emit = defineEmits(['ver', 'outra']);

const { t } = useI18n();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.PRONTO';

const frase = computed(() => {
  const { seguros, pessoas } = props.chegaram;
  return [
    t(`${BASE}.CHEGARAM`, { count: seguros }, seguros),
    t(`${BASE}.DE_PESSOAS`, { count: pessoas }, pessoas),
  ].join(' ');
});
const novas = computed(() => props.chegaram.pessoasNovas ?? 0);
</script>

<template>
  <HeroiEscuro data-carteira="pronto-de-seguros">
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
    <template v-if="novas > 0" #apoio>
      <span data-carteira="pessoas-novas">
        {{ t(`${BASE}.PESSOAS_NOVAS`, { count: novas }, novas) }}
      </span>
    </template>
    <template #acao>
      <Button
        size="lg"
        data-carteira="ver-os-seguros"
        class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!outline-white"
        :label="t(`${BASE}.VER`)"
        @click="emit('ver')"
      />
      <Button
        size="lg"
        data-carteira="trazer-outra"
        class="!bg-white/10 !text-white/90 !outline-white/20 hover:enabled:!bg-white/20 focus-visible:!outline-white"
        :label="t('RELACIONAMENTOS_TRAZER.PRONTO.OUTRA')"
        @click="emit('outra')"
      />
    </template>
  </HeroiEscuro>
</template>
