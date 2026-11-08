<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { nomeCurtoDoAgente } from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import Ressalva from '../comum/Ressalva.vue';
import RessalvasDaConferencia from '../comum/RessalvasDaConferencia.vue';
import CartaoKpi from './CartaoKpi.vue';
import LeiturasRapidas from './LeiturasRapidas.vue';

// #2226 v2 (§2.1) — os 8 números do período, as leituras rápidas e, colados aos números, a ressalva
// do que conta como "fechou" (dado do negócio) e o que a conferência achou da contagem.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.NUMEROS';
const agente = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta.agente?.nome,
    fmt.t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);
</script>

<template>
  <section
    id="numeros"
    aria-labelledby="numeros-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="numeros-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="
        fmt.t(
          painel.meta.periodo?.anterior
            ? `${NS}.DESCRICAO`
            : `${NS}.DESCRICAO_SEM_ANTERIOR`
        )
      "
    />
    <div class="grid grid-cols-2 gap-3 md:grid-cols-4 2xl:grid-cols-8">
      <CartaoKpi
        v-for="kpi in painel.kpis"
        :key="kpi.id"
        :kpi="kpi"
        :nomes="painel.meta.nomes"
        :agente="agente"
        :dias="painel.meta.periodo?.anterior ? painel.meta.periodo.dias : 0"
      />
    </div>
    <div class="grid gap-3 xl:grid-cols-2">
      <Ressalva
        v-if="painel.meta.nomes.fechou_ressalva"
        :destaque="painel.meta.nomes.fechou_ressalva"
        :texto="
          painel.meta.nomes.fechou_explicacao
            ? fmt.t(`${NS}.FECHOU_CONTA`, {
                fechou: painel.meta.nomes.fechou,
                explicacao: painel.meta.nomes.fechou_explicacao,
              })
            : ''
        "
      />
      <RessalvasDaConferencia :painel="painel" parte="kpis" />
    </div>
    <LeiturasRapidas :painel="painel" :agente="agente" />
  </section>
</template>
