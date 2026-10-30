<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { ressalvasDe } from '../../../utils/desempenhoContrato';
import Ressalva from './Ressalva.vue';

// #2226 v2 — o que a conferência achou de uma parte do painel, colado ao número dessa parte
// (ex.: "Por que travou · leitura fraca: os motivos servem para ordenar…"). O texto vem dos dados.
const props = defineProps({
  painel: { type: Object, required: true },
  parte: { type: String, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.COMO_LER';

const campos = computed(() => ressalvasDe(props.painel, props.parte));
const destaque = campo =>
  fmt.t(`${NS}.RESSALVA_DO_CAMPO`, {
    campo: campo.nome,
    leitura: fmt
      .tSeTiver(`${NS}.LEITURA.${String(campo.leitura).toUpperCase()}`, '')
      .toLocaleLowerCase(fmt.idioma.value),
    pct: fmt.pct(campo.acerto_pct),
  });
</script>

<template>
  <Ressalva
    v-for="campo in campos"
    :key="campo.id"
    :data-ressalva-conferencia="campo.id"
    :destaque="destaque(campo)"
    :texto="campo.nota"
  />
</template>
