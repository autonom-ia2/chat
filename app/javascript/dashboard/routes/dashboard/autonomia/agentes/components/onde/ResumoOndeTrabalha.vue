<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import { caixaPeloNome, enderecoDaCaixa } from '../../utils/ondeTrabalha';

// #1366 (protótipo da Fase 2, rodada 2) — "Onde {nome} trabalha": uma linha por caixa (canal,
// papel e assuntos) ou, no ajudante, quem ele ajuda e quando é chamado. Usado na criação (topo,
// Confira e Pronto) e no bloco da página do agente.
const props = defineProps({
  papel: { type: Object, default: null },
  caixas: { type: Array, default: () => [] },
  // Topo da criação: uma faixa curta, sem os assuntos.
  compacto: { type: Boolean, default: false },
});

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.ONDE';

const linhas = computed(() =>
  (props.papel?.caixas || []).map(item => {
    const caixa = caixaPeloNome(props.caixas, item.caixa);
    const assuntos = item.assuntos || [];
    return {
      chave: item.caixa,
      caixa,
      nome: item.caixa,
      endereco: enderecoDaCaixa(caixa),
      papel: t(
        `${NS}.PAPEL.${item.papel === 'primeiro' ? 'PRIMEIRO' : 'RECEBE'}`
      ),
      assuntos: assuntos.length
        ? t(`${NS}.CUIDA_DE`, { assuntos: assuntos.join(', ') })
        : t(`${NS}.SEM_ASSUNTO`),
    };
  })
);
const ajuda = computed(() => props.papel?.tipo === 'ajuda');
</script>

<template>
  <ul v-if="ajuda" class="flex flex-col gap-2 p-0 m-0 list-none">
    <li class="flex items-start gap-3 text-sm text-n-slate-12">
      <span
        aria-hidden="true"
        class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-users size-5" />
      </span>
      <span class="flex flex-col gap-0.5 min-w-0">
        <b class="font-semibold">
          {{ t(`${NS}.AJUDA`, { agentes: papel.ajuda.join(', ') }) }}
        </b>
        <span v-if="!compacto && papel.quando" class="text-n-slate-11">
          {{ papel.quando }}
        </span>
      </span>
    </li>
  </ul>
  <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
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
        <ChannelIcon
          v-if="linha.caixa"
          :inbox="linha.caixa"
          use-brand-icon
          class="size-5"
        />
        <span v-else class="i-lucide-inbox size-5 text-n-slate-11" />
      </span>
      <span class="flex flex-col gap-0.5 min-w-0">
        <span>
          <b class="font-semibold">{{ linha.nome }}</b>
          <span v-if="linha.endereco" class="text-n-slate-11">
            · {{ linha.endereco }}</span
          >
        </span>
        <span class="text-n-slate-11">
          {{ linha.papel
          }}<template v-if="!compacto"> · {{ linha.assuntos }}</template>
        </span>
      </span>
    </li>
  </ul>
</template>
