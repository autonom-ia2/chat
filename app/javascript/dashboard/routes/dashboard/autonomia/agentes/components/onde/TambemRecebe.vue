<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolhaMarcar from '../EscolhaMarcar.vue';
import { chaveDoTipoDaCaixa } from '../../utils/canais';
import {
  BLOQUEIO,
  caixaPeloId,
  enderecoDaCaixa,
  outrasCaixasDaEquipe,
  principalDaCaixa,
  soDePessoas,
} from '../../utils/ondeTrabalha';
import { useAgenteIaPorCaixa } from '../../composables/useAgenteIaPorCaixa';

// #1433 (decisão do Rodrigo de 15/10, "a, para todos os agentes") — na gaveta "Onde e quando {nome}
// responde", logo abaixo de "Onde atende": as OUTRAS caixas em que o agente também recebe quando alguém
// passar (vínculo de área). Várias escolhas, em cartões compactos iguais aos de "Onde atende" (EscolhaMarcar, sem
// lista nativa), com o tipo do canal na etiqueta. Podem ser escolhidas as caixas
// com principal atendendo e as atendidas só por pessoas; outro robô e principal parado ficam bloqueados
// com o motivo. A caixa principal dele (e a escolhida em "Onde atende", em `fora`) não aparece.
// Quem grava é a gaveta (useSalvarEquipe), junto com o resto.
const props = defineProps({
  agenteId: { type: Number, required: true },
  nome: { type: String, required: true },
  // A L2 (canais_ocupados), com `areas` e `so_de_pessoas`; `caixas`: a store de inboxes (ícone e número).
  canais: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
  fora: { type: Array, default: () => [] },
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

// #1648 — com a aba "Agente de IA" por caixa, o canal com agente de outro sistema aceita.
const porCaixa = useAgenteIaPorCaixa();

const MOTIVO = {
  [BLOQUEIO.OUTRO_ROBO]: () => t('AGENTS.JORNADA.EQUIPE.OUTRO_ROBO'),
  [BLOQUEIO.SEM_PRINCIPAL]: () => t('AGENTS.JORNADA.EQUIPE.SEM_PRINCIPAL'),
  [BLOQUEIO.PRINCIPAL_PARADO]: canal =>
    t('AGENTS.JORNADA.EQUIPE.PRINCIPAL_PARADO', {
      outro: principalDaCaixa(canal).agent_name,
    }),
};

const textoDaCaixa = (canal, caixa, bloqueio) => {
  if (soDePessoas(canal)) {
    return t('AGENTS.JORNADA.EQUIPE.SO_PESSOAS', { nome: props.nome });
  }
  const principal = principalDaCaixa(canal);
  if (principal && !bloqueio) {
    return t('AGENTS.JORNADA.EQUIPE.PRINCIPAL', {
      outro: principal.agent_name,
    });
  }
  return enderecoDaCaixa(caixa);
};

const opcoes = computed(() =>
  outrasCaixasDaEquipe(props.canais, props.agenteId, props.fora, {
    comOutroSistema: porCaixa.value,
  }).map(({ canal, bloqueio }) => {
    const caixa = caixaPeloId(props.caixas, canal.inbox_id);
    const tipo = chaveDoTipoDaCaixa(canal);
    return {
      valor: canal.inbox_id,
      titulo: canal.name,
      etiqueta: tipo ? t(`AGENTS.JORNADA.ONDE_QUANDO.TIPO.${tipo}`) : '',
      texto: textoDaCaixa(canal, caixa, bloqueio),
      desabilitada: Boolean(bloqueio),
      motivo: bloqueio ? MOTIVO[bloqueio](canal) : '',
    };
  })
);
</script>

<template>
  <section data-tambem-recebe class="flex flex-col gap-2">
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t('AGENTS.JORNADA.ONDE_QUANDO.TAMBEM') }}
    </h3>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.JORNADA.ONDE_QUANDO.TAMBEM_TEXTO', { nome }) }}
    </p>
    <EscolhaMarcar
      v-if="opcoes.length"
      :model-value="modelValue"
      :rotulo="t('AGENTS.JORNADA.ONDE_QUANDO.TAMBEM')"
      :opcoes="opcoes"
      @update:model-value="emit('update:modelValue', $event)"
    />
    <p v-else data-sem-outras class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.JORNADA.ONDE_QUANDO.TAMBEM_NENHUMA') }}
    </p>
  </section>
</template>
