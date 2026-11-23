<script setup>
// #3099 — embaixo do "Vão receber" da revisão, com as duas versões ligadas: quantos recebem agora (o teste) e quantos
// recebem depois da espera ("Agora vão 270 (o teste). As outras 1.080 vão depois de 4 horas."). No público pequeno,
// todos recebem agora, cada um uma das duas. O "Vão receber" continua sendo o público inteiro.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatNumber } from './localeTag';

const props = defineProps({
  // { modo: 'teste' | 'todos', teste, resto } (recipient_previews ou duasVersoes.js#planoDoTeste)
  plano: { type: Object, required: true },
  // Horas de espera antes de escolher a melhor.
  espera: { type: Number, required: true },
});

const NS = 'DUAS_VERSOES.RESUMO';
const { t, locale } = useI18n();

const frase = computed(() => {
  if (props.plano.modo === 'todos') return t(`${NS}.AGORA_VAO_TODOS`);
  return t(`${NS}.AGORA_VAO`, {
    teste: formatNumber(props.plano.teste, locale.value),
    resto: formatNumber(props.plano.resto, locale.value),
    horas: t('DUAS_VERSOES.REGRA.HORAS', { n: props.espera }, props.espera),
  });
});
</script>

<template>
  <p
    class="m-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-12"
    data-agora-vai-o-teste
  >
    <span class="i-lucide-split mt-0.5 size-4 shrink-0" aria-hidden="true" />
    {{ frase }}
  </p>
</template>
