<script setup>
import { useI18n } from 'vue-i18n';
import { formatarDia } from '../../trazer/prazo';
import { PONTO } from '../comum/ponto';

// #2894 — a linha de detalhe de uma lista trazida: quando, quem e quantas
// pessoas. Fica à parte para o histórico da carteira (#2897) mostrar a mesma
// linha nas listas de pessoas.
defineProps({
  lista: { type: Object, required: true },
});

const { t, locale } = useI18n();
const dia = ms => formatarDia(ms, locale.value);
</script>

<template>
  {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.EM', { data: dia(lista.quando) }) }}
  {{ PONTO }}
  {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.POR', { nome: lista.quem }) }}
  {{ PONTO }}
  <span class="tabular-nums">
    {{
      t(
        'RELACIONAMENTOS_TRAZER.HISTORICO.PESSOAS',
        { count: lista.total },
        lista.total
      )
    }}
  </span>
</template>
