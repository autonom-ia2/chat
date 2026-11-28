<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { faixaDoPlano } from '../../utils/planoDoContratado';

// #3270 — a faixa do período grátis no topo da página do agente contratado (o Banner do painel). Durante o grátis:
// quantos dias faltam e o preço depois. Pausado: o agente não responde aos clientes, e quem libera é a Hub2You. Conta
// liberada: nenhuma faixa (quem usa só monta com `mostraFaixa`). O estado e o preço vêm do servidor
// (`contratado.plano`).
const props = defineProps({
  plano: { type: Object, required: true },
});

const { t, locale } = useI18n();

const faixa = computed(() => faixaDoPlano(t, props.plano, locale.value));
</script>

<template>
  <Banner :color="faixa.cor" :data-faixa-plano="faixa.situacao" role="status">
    <span class="flex items-start gap-2 text-base">
      <span
        class="mt-0.5 size-5 shrink-0"
        :class="faixa.icone"
        aria-hidden="true"
      />
      {{ faixa.texto }}
    </span>
  </Banner>
</template>
