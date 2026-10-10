<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteErro from '../AgenteErro.vue';
import { idiomaDoNavegador } from '../../utils/pagina';

// #1181 PR3 (protótipo t07-conversas) — "Conversas desta semana": as conversas por trás dos números,
// nas abas Respondidas e Passadas para a equipe. Lê o drilldown que já existe
// (`analytics/conversations`, 7 dias, até 50, as mais recentes): "passadas" = handed_off; "respondidas"
// = handled, a lista de conversas tratadas pelo agente que o backend tem hoje. Cada linha abre a
// conversa numa aba nova do painel.
const props = defineProps({
  agentId: { type: Number, required: true },
  aba: { type: String, default: 'respondidas' },
});

const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const router = useRouter();
const NS = 'AGENTS.JORNADA.PAGINA.CONVERSAS';
const METRICA = { respondidas: 'handled', passadas: 'handed_off' };

const atual = ref(props.aba);
const estado = ref('carregando');
const linhas = ref([]);
const temMais = ref(false);
let pedido = 0;

const carregar = async () => {
  pedido += 1;
  const meu = pedido;
  estado.value = 'carregando';
  try {
    const { data } = await AutonomiaAgentsAPI.analyticsConversations(
      props.agentId,
      { range: '7d', metric: METRICA[atual.value] }
    );
    if (meu !== pedido) return;
    linhas.value = (data?.payload || []).filter(
      linha => linha.conversation?.display_id
    );
    temMais.value = data?.meta?.has_more === true;
    estado.value = 'pronto';
  } catch {
    if (meu !== pedido) return;
    estado.value = 'erro';
  }
};

watch(atual, carregar, { immediate: true });

const quando = segundos =>
  new Date(segundos * 1000).toLocaleString(idiomaDoNavegador(locale.value), {
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });

const contato = linha => linha.conversation.contact_name || t(`${NS}.SEM_NOME`);

const linkDa = linha =>
  router.resolve({
    name: 'inbox_conversation',
    params: { conversation_id: linha.conversation.display_id },
  }).href;

const abas = computed(() => [
  { chave: 'respondidas', texto: t(`${NS}.RESPONDIDAS`) },
  { chave: 'passadas', texto: t(`${NS}.PASSADAS`) },
]);
</script>

<template>
  <AgenteGaveta larga :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <div
      role="group"
      :aria-label="t(`${NS}.MOSTRAR`)"
      class="flex flex-wrap gap-2"
    >
      <button
        v-for="item in abas"
        :key="item.chave"
        type="button"
        :data-aba="item.chave"
        :aria-pressed="atual === item.chave ? 'true' : 'false'"
        class="px-4 text-sm font-medium rounded-full min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        :class="
          atual === item.chave
            ? 'bg-n-blue-2 ring-n-blue-11 text-n-slate-12'
            : 'bg-n-solid-1 ring-n-slate-7 text-n-slate-12 hover:bg-n-slate-2'
        "
        @click="atual = item.chave"
      >
        {{ item.texto }}
      </button>
    </div>

    <div v-if="estado === 'carregando'" class="flex justify-center py-6">
      <p role="status" class="sr-only">{{ t(`${NS}.CARREGANDO`) }}</p>
      <Spinner :size="24" aria-hidden="true" />
    </div>
    <AgenteErro
      v-else-if="estado === 'erro'"
      :titulo="t(`${NS}.ERRO`)"
      :garantia="t(`${NS}.ERRO_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="carregar"
    />
    <template v-else>
      <ul
        v-if="linhas.length"
        :aria-label="abas.find(item => item.chave === atual).texto"
        class="flex flex-col gap-1 p-0 m-0 list-none"
      >
        <li
          v-for="linha in linhas"
          :key="linha.conversation.id"
          data-linha
          class="flex items-center gap-3 py-2"
        >
          <span
            aria-hidden="true"
            class="grid text-sm font-semibold rounded-full place-items-center size-9 shrink-0 bg-n-slate-3 text-n-slate-11"
          >
            {{ contato(linha).charAt(0).toUpperCase() }}
          </span>
          <span class="flex flex-col min-w-0 grow">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ contato(linha) }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{
                quando(linha.occurred_at || linha.conversation.last_activity_at)
              }}
            </span>
          </span>
          <a
            :href="linkDa(linha)"
            target="_blank"
            rel="noopener noreferrer"
            :aria-label="t(`${NS}.ABRIR_ARIA`, { contato: contato(linha) })"
            class="inline-flex items-center px-3 text-sm font-semibold rounded-xl min-h-11 text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          >
            {{ t(`${NS}.ABRIR`) }}
          </a>
        </li>
      </ul>
      <p v-else data-vazio class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.VAZIO`) }}
      </p>
      <p v-if="temMais" class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.LIMITE`) }}
      </p>
    </template>
  </AgenteGaveta>
</template>
