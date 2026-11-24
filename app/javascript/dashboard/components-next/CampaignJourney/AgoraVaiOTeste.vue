<script setup>
// #3099 — no subtítulo do "Vão receber" da revisão, com as duas versões ligadas: quantos recebem agora (o teste) e
// quantos depois da espera, numa frase só com o canal ("SMS · 270 agora, 1.080 depois de 4 horas"). Agendada, a hora
// marcada no lugar do "agora". No público pequeno, todos recebem de uma vez, cada um uma das duas. O número grande do
// "Vão receber" continua sendo o público inteiro.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatNumber } from './localeTag';

const props = defineProps({
  // { modo: 'teste' | 'todos', teste, resto } (recipient_previews ou duasVersoes.js#planoDoTeste)
  plano: { type: Object, required: true },
  // Horas de espera antes de escolher a melhor.
  espera: { type: Number, required: true },
  // A data e hora marcadas (StepReview, no fuso da conta); vazio = agora.
  quando: { type: String, default: '' },
});

const NS = 'DUAS_VERSOES.RESUMO';
const { t, locale } = useI18n();

const frase = computed(() => {
  const quando = props.quando;
  if (props.plano.modo === 'todos')
    return quando
      ? t(`${NS}.DEPOIS_VAO_TODOS`, { quando })
      : t(`${NS}.AGORA_VAO_TODOS`);
  const numeros = {
    teste: formatNumber(props.plano.teste, locale.value),
    resto: formatNumber(props.plano.resto, locale.value),
    horas: t('DUAS_VERSOES.REGRA.HORAS', { n: props.espera }, props.espera),
  };
  return quando
    ? t(`${NS}.DEPOIS_VAO`, { ...numeros, quando })
    : t(`${NS}.AGORA_VAO`, numeros);
});
</script>

<template>
  <span data-agora-vai-o-teste>{{ frase }}</span>
</template>
