<script setup>
import { computed, ref } from 'vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import TabelaDoPainel from './TabelaDoPainel.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { nomeCurtoDoAgente, nomeDe } from '../../../utils/desempenhoContrato';
import { ordenar } from '../../../utils/desempenhoDetalhe';

// #2226 v2 — cada tema com volume, resultado, qualidade do agente, o que mais trava e a mudança
// contra o período anterior. Clicar no tema abre as procuras dele.
const props = defineProps({
  painel: { type: Object, required: true },
});

const emit = defineEmits(['filtrar']);
const { t, n, pct } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.TEMA';
const ordem = ref({ coluna: 'procuras', sentido: 'desc' });
const nomes = computed(() => props.painel.meta?.nomes || {});
const nomeDaIa = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta?.agente?.nome,
    t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);

const linhas = computed(() =>
  ordenar(
    (props.painel.temas?.ranking || []).map(tema => ({
      ...tema,
      chave: tema.id,
      trava: tema.motivo_principal_id
        ? nomeDe(props.painel.catalogo, 'motivos', tema.motivo_principal_id)
        : null,
      delta:
        tema.anterior_procuras === null || tema.anterior_procuras === undefined
          ? null
          : tema.procuras - tema.anterior_procuras,
    })),
    ordem.value
  )
);

const numero = (id, titulo, formato = 'numero') => ({
  id,
  titulo,
  alinhar: 'fim',
  ordenavel: true,
  formato,
});
const colunas = computed(() => [
  { id: 'nome', titulo: t(`${B}.COL.TEMA`), ordenavel: true },
  numero('procuras', t(`${B}.COL.PROCURAS`)),
  numero('pct', t(`${B}.COL.PCT`), 'pct'),
  numero('compra', nomes.value.compra || t(`${B}.COL.COMPRA`)),
  numero('fecharam', nomes.value.fechou || t(`${B}.COL.FECHARAM`)),
  numero('taxa_pct', t(`${B}.COL.TAXA`), 'pct'),
  numero('acerto_pct', t(`${B}.COL.ACERTO`, { nome: nomeDaIa.value }), 'pct'),
  numero('erro_grave_pct', t(`${B}.COL.ERRO_GRAVE`), 'pct'),
  { id: 'trava', titulo: t(`${B}.COL.TRAVA`), ordenavel: true },
  numero('delta', t(`${B}.COL.DELTA`)),
]);

const setaDoDelta = valor => {
  if (valor > 0) return '▲';
  if (valor < 0) return '▼';
  return '=';
};
const textoDoDelta = valor => {
  if (valor > 0) return t(`${B}.DELTA_MAIS`, { n: n(valor) });
  if (valor < 0) return t(`${B}.DELTA_MENOS`, { n: n(-valor) });
  return t(`${B}.DELTA_IGUAL`);
};

const maiorTaxa = computed(() =>
  Math.max(...linhas.value.map(linha => linha.taxa_pct ?? -1))
);
</script>

<template>
  <CartaoDoPainel
    :titulo="t(`${B}.TITULO`)"
    :descricao="t(`${B}.DESCRICAO`, { nome: nomeDaIa })"
    :unidade="t(`${B}.UNIDADE`)"
  >
    <TabelaDoPainel
      :colunas="colunas"
      :linhas="linhas"
      :ordem="ordem"
      :legenda="t(`${B}.TITULO`)"
      largura-minima="min-w-[60rem]"
      @ordenar="ordem = $event"
    >
      <template #celula-nome="{ linha }">
        <button
          type="button"
          class="min-h-11 -my-2.5 text-start font-semibold text-n-blue-11 underline-offset-4 hover:underline"
          :data-tema="linha.id"
          :aria-label="t(`${B}.VER_PROCURAS`, { tema: linha.nome })"
          @click="emit('filtrar', { tema: linha.id })"
        >
          {{ linha.nome || t('AGENTS.DESEMPENHO2.B.SEM_NOME') }}
        </button>
      </template>
      <template #celula-fecharam="{ valor }">
        <span class="font-semibold text-n-teal-11">{{ n(valor) }}</span>
      </template>
      <template #celula-taxa_pct="{ linha }">
        <span
          :class="
            linha.taxa_pct !== null && linha.taxa_pct === maiorTaxa
              ? 'font-semibold text-n-teal-11'
              : ''
          "
        >
          {{ pct(linha.taxa_pct) }}
        </span>
      </template>
      <template #celula-erro_grave_pct="{ valor }">
        <span :class="valor ? 'text-n-ruby-11' : ''">
          {{ pct(valor) }}
        </span>
      </template>
      <template #celula-trava="{ valor }">{{ valor || '—' }}</template>
      <template #celula-delta="{ valor }">
        <span
          v-if="valor !== null && valor !== undefined"
          class="whitespace-nowrap"
          :class="valor > 0 ? 'text-n-blue-11' : 'text-n-slate-11'"
        >
          <span aria-hidden="true">{{ setaDoDelta(valor) }}</span>
          {{ textoDoDelta(valor) }}
        </span>
        <span v-else>{{ t('AGENTS.DESEMPENHO2.A.COMUM.SEM_VALOR') }}</span>
      </template>
    </TabelaDoPainel>
  </CartaoDoPainel>
</template>
