<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import QuemAtendeAPI from 'dashboard/api/autonomia/quemAtende';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AgenteAvatar from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteAvatar.vue';
import AgenteBotao from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteBotao.vue';

// #1648 (mockup-2) — aba "Agente de IA" da caixa. Todos são agentes de IA: os
// da plataforma e os de outro sistema (webhook) aparecem juntos, sem rótulo.
// Mostra quem atende primeiro, quem também recebe quando alguém passa e uma
// escolha só: trocar quem atende primeiro. A troca pede confirmação em linha e
// o servidor faz a troca completa por trás. Sem erro de leitura na tela:
// enquanto não lê, fica carregando e tenta de novo sozinho.
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const NINGUEM = 'ninguem';
const NOVA_TENTATIVA_MS = 3000;

const { t } = useI18n();
const store = useStore();
const podeTrocar = useCanManage('inbox_manage');
const agentesDaPlataforma = useMapGetter('autonomiaAgents/getRecords');
const agentesDeOutroSistema = useMapGetter('agentBots/getBots');

const inboxId = computed(() => Number(props.inbox?.id));
// [{ id, name, papel, origem, avatar_url? }] ou null enquanto carrega.
const daCaixa = ref(null);
const escolhido = ref('');
const trocando = ref(false);
let relogio = null;

const chave = agente => (agente ? `${agente.origem}:${agente.id}` : NINGUEM);

const principal = computed(
  () => daCaixa.value?.find(agente => agente.papel === 'porta') || null
);
const equipe = computed(
  () => daCaixa.value?.filter(agente => agente.papel === 'area') || []
);
const chaveAtual = computed(() =>
  principal.value ? chave(principal.value) : ''
);

const todos = computed(() =>
  [
    ...(agentesDaPlataforma.value || [])
      .filter(
        agente => agente.status !== 'draft' && agente.actuation !== 'internal'
      )
      .map(agente => ({ ...agente, origem: 'plataforma' })),
    ...(agentesDeOutroSistema.value || []).map(agente => ({
      ...agente,
      origem: 'webhook',
    })),
  ].sort((a, b) => a.name.localeCompare(b.name))
);

const opcoes = computed(() => [
  ...(principal.value
    ? [{ value: NINGUEM, label: t('AGENTS.CAIXA_AGENTE_IA.NINGUEM_OPCAO') }]
    : []),
  ...todos.value.map(agente => ({ value: chave(agente), label: agente.name })),
]);

const novo = computed(() =>
  todos.value.find(agente => chave(agente) === escolhido.value)
);
const pendente = computed(
  () => Boolean(escolhido.value) && escolhido.value !== chaveAtual.value
);

const textoDaConfirmacao = computed(() => {
  const antes = principal.value?.name;
  if (escolhido.value === NINGUEM) {
    return t('AGENTS.CAIXA_AGENTE_IA.CONFIRMA_TIRAR', { antes });
  }
  const depois = novo.value?.name;
  return antes
    ? t('AGENTS.CAIXA_AGENTE_IA.CONFIRMA_TROCA', { antes, depois })
    : t('AGENTS.CAIXA_AGENTE_IA.CONFIRMA_NOVO', { depois });
});

const tambemRecebem = computed(() =>
  t('AGENTS.CAIXA_AGENTE_IA.TAMBEM_RECEBEM', {
    nomes: equipe.value.map(agente => agente.name).join(', '),
  })
);

const rotaDoAgente = agente =>
  agente.origem === 'webhook'
    ? { name: 'autonomia_agents_index', query: { outro: agente.id } }
    : { name: 'autonomia_agent_panel', params: { agentId: agente.id } };

const carregar = async () => {
  try {
    const { data } = await QuemAtendeAPI.daCaixa(inboxId.value);
    daCaixa.value = data.agentes;
    escolhido.value = chaveAtual.value;
  } catch {
    relogio = setTimeout(carregar, NOVA_TENTATIVA_MS);
  }
};

const cancelar = () => {
  escolhido.value = chaveAtual.value;
};

const trocar = async () => {
  if (trocando.value) return;
  trocando.value = true;
  const alvo = escolhido.value === NINGUEM ? null : novo.value;
  try {
    await QuemAtendeAPI.trocar(
      inboxId.value,
      alvo && { id: alvo.id, origem: alvo.origem }
    );
    useAlert(
      alvo
        ? t('AGENTS.CAIXA_AGENTE_IA.TROCOU', { nome: alvo.name })
        : t('AGENTS.CAIXA_AGENTE_IA.TIROU')
    );
    await carregar();
  } catch {
    useAlert(t('AGENTS.CAIXA_AGENTE_IA.FALHOU'));
    cancelar();
  } finally {
    trocando.value = false;
  }
};

onMounted(() => {
  store.dispatch('autonomiaAgents/get');
  store.dispatch('agentBots/get');
  carregar();
});
onBeforeUnmount(() => clearTimeout(relogio));
</script>

<template>
  <div class="mx-6 flex max-w-3xl flex-col gap-6">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ t('AGENTS.CAIXA_AGENTE_IA.TITULO') }}
    </h2>

    <template v-if="!daCaixa">
      <p role="status" class="sr-only">
        {{ t('AGENTS.CAIXA_AGENTE_IA.CARREGANDO') }}
      </p>
      <div
        data-esqueleto
        aria-hidden="true"
        class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
      >
        <span class="flex items-center gap-3">
          <span
            class="size-12 rounded-full bg-n-slate-3 motion-safe:animate-pulse"
          />
          <span
            class="h-4 w-2/5 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
          />
        </span>
        <span
          class="h-3.5 w-3/4 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
        />
        <span
          class="h-3.5 w-1/2 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
        />
      </div>
      <span
        aria-hidden="true"
        class="h-11 w-full max-w-md rounded-xl bg-n-slate-3 motion-safe:animate-pulse"
      />
    </template>

    <template v-else>
      <section
        data-quem-atende
        class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
      >
        <div
          v-if="principal"
          class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3"
        >
          <div class="flex min-w-0 flex-1 items-center gap-3">
            <AgenteAvatar
              :nome="principal.name"
              :src="principal.avatar_url || ''"
              tom="atendendo"
            />
            <div class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span class="text-sm font-medium text-n-teal-11">
                {{ t('AGENTS.CAIXA_AGENTE_IA.ATENDE_PRIMEIRO') }}
              </span>
              <span class="truncate text-base font-semibold text-n-slate-12">
                {{ principal.name }}
              </span>
              <span class="text-sm text-n-slate-11">
                {{ t('AGENTS.CAIXA_AGENTE_IA.ATENDE_PRIMEIRO_TEXTO') }}
              </span>
            </div>
          </div>
          <router-link
            :to="rotaDoAgente(principal)"
            data-abrir-agente
            class="-ms-3 inline-flex min-h-11 items-center gap-1.5 self-start rounded-xl px-3 text-sm font-semibold text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 sm:ms-0 sm:self-auto"
          >
            {{ t('AGENTS.CAIXA_AGENTE_IA.ABRIR') }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </router-link>
        </div>
        <div v-else data-ninguem class="flex items-start gap-3">
          <span
            class="grid size-12 shrink-0 place-items-center rounded-full bg-n-slate-3 text-n-slate-11"
            aria-hidden="true"
          >
            <span class="i-lucide-users size-5" />
          </span>
          <div class="flex flex-col gap-0.5">
            <span class="text-base font-semibold text-n-slate-12">
              {{ t('AGENTS.CAIXA_AGENTE_IA.NINGUEM') }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t('AGENTS.CAIXA_AGENTE_IA.NINGUEM_TEXTO') }}
            </span>
          </div>
        </div>
        <p
          v-if="equipe.length"
          data-tambem-recebem
          class="m-0 flex items-start gap-2 border-t border-n-weak pt-4 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-users mt-0.5 size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          {{ tambemRecebem }}
        </p>
      </section>

      <div v-if="podeTrocar" class="flex max-w-md flex-col gap-2">
        <label
          for="quem-atende-primeiro"
          class="m-0 text-sm font-medium text-n-slate-12"
        >
          {{ t('AGENTS.CAIXA_AGENTE_IA.CAMPO') }}
        </label>
        <ChoiceSelect
          v-model="escolhido"
          trigger-id="quem-atende-primeiro"
          class="w-full [&_button]:w-full"
          :options="opcoes"
          :aria-label="t('AGENTS.CAIXA_AGENTE_IA.CAMPO')"
          :placeholder="t('AGENTS.CAIXA_AGENTE_IA.ESCOLHER')"
          :disabled="trocando"
        />
        <p v-if="!pendente" class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.CAIXA_AGENTE_IA.CAMPO_AJUDA') }}
        </p>
      </div>

      <div
        v-if="pendente"
        data-confirmacao
        role="group"
        :aria-label="t('AGENTS.CAIXA_AGENTE_IA.CAMPO')"
        class="flex max-w-xl flex-col gap-3 rounded-2xl bg-n-amber-2 p-4 ring-1 ring-inset ring-n-amber-6"
      >
        <p
          class="m-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
          aria-live="polite"
        >
          <span
            class="i-lucide-arrow-left-right mt-0.5 size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ textoDaConfirmacao }}
        </p>
        <div class="flex flex-wrap gap-2">
          <AgenteBotao data-trocar :carregando="trocando" @click="trocar">
            {{
              principal
                ? t('AGENTS.CAIXA_AGENTE_IA.TROCAR')
                : t('AGENTS.CAIXA_AGENTE_IA.CONFIRMAR')
            }}
          </AgenteBotao>
          <AgenteBotao
            data-cancelar
            variante="contorno"
            :desabilitado="trocando"
            @click="cancelar"
          >
            {{ t('AGENTS.CAIXA_AGENTE_IA.CANCELAR') }}
          </AgenteBotao>
        </div>
      </div>
    </template>
  </div>
</template>
