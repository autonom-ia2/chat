<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteAvatar from './AgenteAvatar.vue';
import AgenteStatus from './AgenteStatus.vue';
import { ESTADO } from '../utils/estadoDoAgente';

// #1648 (mockup-2) — cartão do agente de outro sistema (agent_bot webhook) na mesma lista dos
// agentes da plataforma, sem seção à parte. O desenho é o do AgenteCartao; a diferença é discreta:
// no lugar dos números da semana, uma linha diz que ele é conectado por endereço de webhook, e o
// clique abre a página dele, a mesma dos nossos agentes (rota do agente com `?origem=webhook`).
// `canais`: nomes das caixas em que atende primeiro (L2), ou null sem a leitura.
const props = defineProps({
  agente: { type: Object, required: true },
  canais: { type: Array, default: null },
  // Endereço da página do agente: abrir em outra aba continua funcionando.
  href: { type: String, required: true },
});

const emit = defineEmits(['abrir']);

const { t } = useI18n();
const atendendo = computed(() => Boolean(props.canais?.length));
const estado = computed(() =>
  atendendo.value ? ESTADO.ATENDENDO : ESTADO.PARADO
);
const aoClicar = evento => {
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button) {
    return;
  }
  evento.preventDefault();
  emit('abrir', props.agente);
};

const onde = computed(() => {
  const total = props.canais?.length || 0;
  if (!total) return t('AGENTS.JORNADA.CARTAO.ONDE_NENHUM');
  if (total === 1) {
    return t('AGENTS.JORNADA.CARTAO.ONDE_CANAL', { canal: props.canais[0] });
  }
  return t('AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS', { n: total }, total);
});
</script>

<template>
  <li data-cartao data-outro-sistema class="list-none">
    <a
      :href="href"
      class="flex flex-col w-full h-full gap-3 p-5 transition shadow-sm text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 hover:ring-n-slate-7 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      @click="aoClicar"
    >
      <span class="flex items-start w-full gap-3">
        <AgenteAvatar
          :nome="agente.name"
          :src="agente.thumbnail || ''"
          :tom="atendendo ? 'atendendo' : 'neutro'"
        />
        <span class="flex flex-col gap-1 grow min-w-0">
          <span class="text-base font-semibold truncate text-n-slate-12">
            {{ agente.name }}
          </span>
          <AgenteStatus :estado="estado" />
        </span>
        <span
          class="mt-3 i-lucide-chevron-right size-5 text-n-slate-10 rtl:rotate-180"
          aria-hidden="true"
        />
      </span>
      <span data-onde class="text-sm text-n-slate-12">{{ onde }}</span>
      <span
        data-conectado-por
        class="flex items-center gap-1.5 text-sm text-n-slate-11"
      >
        <span class="i-lucide-link size-4 shrink-0" aria-hidden="true" />
        {{ t('AGENTS.OUTRO_SISTEMA.CONECTADO_POR') }}
      </span>
    </a>
  </li>
</template>
