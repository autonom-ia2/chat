<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import {
  caixaPeloId,
  enderecoDaCaixa,
  soDePessoas,
} from '../../utils/ondeTrabalha';

// #1433 (tema 13) — "Onde {nome} trabalha" do agente da equipe: uma linha por caixa, só com a caixa e o
// papel ("Recebe quando alguém passar"; na caixa só de pessoas, diz que ela é atendida só por pessoas).
// Usado no Pronto da criação e na página do agente.
// Os assuntos (funis) de que ele cuida não aparecem aqui ainda: a tela do CRM que os escolhe não existe.
// `canais`: linhas da L2 (canais_ocupados) em que o agente está na equipe; `caixas`: a store de inboxes.
const props = defineProps({
  canais: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
});

const { t } = useI18n();

const linhas = computed(() =>
  props.canais.map(canal => {
    const caixa = caixaPeloId(props.caixas, canal.inbox_id);
    return {
      chave: canal.inbox_id,
      caixa: caixa || { channel_type: canal.channel_type },
      nome: canal.name,
      endereco: enderecoDaCaixa(caixa),
      papel: soDePessoas(canal)
        ? t('AGENTS.JORNADA.ONDE.RECEBE_PESSOAS')
        : t('AGENTS.JORNADA.ONDE.RECEBE'),
    };
  })
);
</script>

<template>
  <ul data-resumo-onde class="flex flex-col gap-3 p-0 m-0 list-none">
    <li
      v-for="linha in linhas"
      :key="linha.chave"
      data-linha-caixa
      class="flex items-start gap-3 text-sm text-n-slate-12"
    >
      <span
        aria-hidden="true"
        class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
      >
        <ChannelIcon :inbox="linha.caixa" use-brand-icon class="size-5" />
      </span>
      <span class="flex flex-col gap-0.5 min-w-0">
        <span>
          <b class="font-semibold">{{ linha.nome }}</b>
          <span v-if="linha.endereco" class="text-n-slate-11">
            {{ `· ${linha.endereco}` }}
          </span>
        </span>
        <span class="text-n-slate-11">{{ linha.papel }}</span>
      </span>
    </li>
  </ul>
</template>
