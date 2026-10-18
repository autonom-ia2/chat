<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';

// #1428 (parte 3, piloto) — a faixa discreta acima da conversa nova: a última mudança feita
// conversando que ainda dá para desfazer (o servidor manda no agente, mesmo depois de recarregar a
// página). Some quando o agente muda; depois disso o caminho é "Jeitos anteriores de responder".
const props = defineProps({
  // { thread_id, linhas: [resumos] }
  ultima: { type: Object, required: true },
  nome: { type: String, required: true },
  desfazendo: { type: Boolean, default: false },
  // '' | 'mudou' (409: o agente mudou depois) | 'falhou'
  erro: { type: String, default: '' },
});

const emit = defineEmits(['desfazer']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CONFERIDO';

const texto = computed(() =>
  props.ultima.linhas?.length
    ? t(`${NS}.ULTIMA_MUDANCA`, { lista: props.ultima.linhas.join('; ') })
    : t(`${NS}.ULTIMA_MUDANCA_SEM_RESUMO`)
);
// O que o dono não pediu, com o mesmo texto do cartão.
const semPedido = computed(() =>
  props.ultima.sem_pedido?.length
    ? t(`${NS}.SEM_PEDIDO`, { lista: props.ultima.sem_pedido.join('; ') })
    : ''
);
</script>

<template>
  <div
    data-ultima-mudanca
    class="flex flex-wrap items-center gap-3 px-4 py-2 text-sm rounded-xl bg-n-slate-2 text-n-slate-12"
  >
    <span
      class="i-lucide-history size-4 shrink-0 text-n-slate-11"
      aria-hidden="true"
    />
    <span class="flex flex-col gap-1 grow">
      <span>{{ texto }}</span>
      <span v-if="semPedido" data-ultima-sem-pedido>{{ semPedido }}</span>
    </span>
    <AgenteBotao
      v-if="erro !== 'mudou'"
      data-desfazer-ultima
      variante="fantasma"
      icone="i-lucide-undo-2"
      :carregando="desfazendo"
      :rotulo-carregando="t(`${NS}.DESFAZENDO`)"
      @click="emit('desfazer')"
    >
      {{ t(`${NS}.DESFAZER`) }}
    </AgenteBotao>
    <p
      v-if="erro"
      data-erro-desfazer
      role="alert"
      class="w-full m-0 text-sm text-n-slate-12"
    >
      {{
        erro === 'mudou'
          ? t(`${NS}.MUDOU_DEPOIS`, { nome })
          : t(`${NS}.ERRO`, { nome })
      }}
    </p>
  </div>
</template>
