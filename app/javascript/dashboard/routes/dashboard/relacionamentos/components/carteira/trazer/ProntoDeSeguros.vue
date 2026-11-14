<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BOTAO_DISCRETO_DO_HEROI,
  BOTAO_PRINCIPAL_DO_HEROI,
} from '../../../carteira/botoesDoHeroi';
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
        :class="BOTAO_PRINCIPAL_DO_HEROI"
        :label="t(`${BASE}.VER`)"
        @click="emit('ver')"
      />
      <Button
        size="lg"
        data-carteira="trazer-outra"
        :class="BOTAO_DISCRETO_DO_HEROI"
        :label="t('RELACIONAMENTOS_TRAZER.PRONTO.OUTRA')"
        @click="emit('outra')"
      />
    </template>
  </HeroiEscuro>
</template>
