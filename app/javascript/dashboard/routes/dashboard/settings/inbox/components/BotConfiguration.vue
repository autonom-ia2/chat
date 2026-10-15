<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import QuemAtendeAPI from 'dashboard/api/autonomia/quemAtende';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AgenteAvatar from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteAvatar.vue';
import AgenteBotao from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteBotao.vue';
import { useJornadaAtiva } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useJornadaAtiva';

// #1648 — aba "Agente de IA" da caixa. Todos são agentes de IA: os da
// plataforma e os de outro sistema (webhook) aparecem juntos, sem rótulo.
// Mostra quem atende primeiro, quem também recebe quando alguém passa e uma
// escolha só: trocar quem atende primeiro. As opções vêm do servidor, com o
// motivo de recusa de cada uma (a tela avisa antes de pedir). A troca pede
// confirmação em linha e o servidor faz a troca completa por trás. Sem erro de
// leitura na tela: enquanto não lê, fica carregando e tenta de novo sozinho.
// A confirmação segue o padrão das telas de agentes (aviso dentro da escolha,
// Cancelar e Trocar no rodapé do bloco).
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const NINGUEM = 'ninguem';
const NOVA_TENTATIVA_MS = 3000;
const RECUSAS = [
  'agente_interno',
  'agente_rascunho',
  'agente_parado',
  'agente_ja_e_da_equipe',
  'mudou_agora',
];

const { t } = useI18n();
const podeTrocar = useCanManage('inbox_manage');
const jornadaAtiva = useJornadaAtiva();

const inboxId = computed(() => Number(props.inbox?.id));
// { agentes, primeiro, opcoes } ou null enquanto carrega.
const leitura = ref(null);
const escolhido = ref('');
const trocando = ref(false);
// Código da recusa do servidor na última troca (a tela mostra o motivo).
const recusaDaTroca = ref(null);
let relogio = null;

const chave = agente => (agente ? `${agente.tipo}:${agente.id}` : NINGUEM);

const principal = computed(
  () => leitura.value?.agentes.find(agente => agente.papel === 'porta') || null
);
const equipe = computed(
  () => leitura.value?.agentes.filter(agente => agente.papel === 'area') || []
);
const chaveAtual = computed(() =>
  principal.value ? chave(principal.value) : ''
);

const opcoes = computed(() => [
  ...(principal.value
    ? [{ value: NINGUEM, label: t('AGENTS.CAIXA_AGENTE_IA.NINGUEM_OPCAO') }]
    : []),
  ...(leitura.value?.opcoes || []).map(agente => ({
    value: chave(agente),
    label: agente.name,
  })),
]);

const novo = computed(() =>
  (leitura.value?.opcoes || []).find(
    agente => chave(agente) === escolhido.value
  )
);
const pendente = computed(
  () => Boolean(escolhido.value) && escolhido.value !== chaveAtual.value
);

const textoDaRecusa = codigo =>
  RECUSAS.includes(codigo)
    ? t(`AGENTS.CAIXA_AGENTE_IA.RECUSA.${codigo.toUpperCase()}`, {
        nome: novo.value?.name || '',
      })
    : '';
// O motivo de não dar para trocar: o que o servidor já disse da opção, ou o
// que respondeu na última tentativa.
const recusa = computed(() =>
  pendente.value ? textoDaRecusa(recusaDaTroca.value || novo.value?.recusa) : ''
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

// Agente de outro sistema abre a página dele na lista nova de Agentes; sem a
// jornada, a lista de Configurações › Robôs, onde ele se edita.
const rotaDoAgente = agente => {
  if (agente.tipo !== 'webhook') {
    return { name: 'autonomia_agent_panel', params: { agentId: agente.id } };
  }
  if (!jornadaAtiva) return { name: 'agent_bots' };
  return {
    name: 'autonomia_agent_panel',
    params: { agentId: agente.id },
    query: { origem: 'webhook' },
  };
};

const mostrar = dados => {
  leitura.value = dados;
  escolhido.value = chaveAtual.value;
};

const carregar = async () => {
  clearTimeout(relogio);
  try {
    const { data } = await QuemAtendeAPI.daCaixa(inboxId.value);
    mostrar(data);
  } catch {
    relogio = setTimeout(carregar, NOVA_TENTATIVA_MS);
  }
};

const escolher = valor => {
  escolhido.value = valor;
  recusaDaTroca.value = null;
};

const cancelar = () => escolher(chaveAtual.value);

const trocar = async () => {
  if (trocando.value || recusa.value) return;
  trocando.value = true;
  const alvo = escolhido.value === NINGUEM ? null : novo.value;
  try {
    const { data } = await QuemAtendeAPI.trocar(
      inboxId.value,
      alvo && { tipo: alvo.tipo, id: alvo.id }
    );
    useAlert(
      alvo
        ? t('AGENTS.CAIXA_AGENTE_IA.TROCOU', { nome: alvo.name })
        : t('AGENTS.CAIXA_AGENTE_IA.TIROU')
    );
    mostrar(data);
  } catch (erro) {
    const codigo = erro?.response?.data?.code;
    if (RECUSAS.includes(codigo)) {
      recusaDaTroca.value = codigo;
    } else {
      useAlert(t('AGENTS.CAIXA_AGENTE_IA.FALHOU'));
      cancelar();
    }
    if (codigo === 'mudou_agora') carregar();
  } finally {
    trocando.value = false;
  }
};

onMounted(carregar);
onBeforeUnmount(() => clearTimeout(relogio));
</script>

<template>
  <div class="mx-6 flex max-w-3xl flex-col gap-6">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ t('AGENTS.CAIXA_AGENTE_IA.TITULO') }}
    </h2>

    <template v-if="!leitura">
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

    <section
      v-else
      data-quem-atende
      class="flex flex-col divide-y divide-n-weak rounded-2xl bg-n-solid-1 shadow-sm ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div
        v-if="principal"
        class="flex flex-col gap-2 p-5 sm:flex-row sm:items-center sm:gap-3"
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
      <div v-else data-ninguem class="flex items-start gap-3 p-5">
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
        class="m-0 flex items-start gap-2 p-5 text-sm text-n-slate-12"
      >
        <span
          class="i-lucide-users mt-0.5 size-4 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{ tambemRecebem }}
      </p>

      <div v-if="podeTrocar" class="flex flex-col gap-2 p-5">
        <label
          for="quem-atende-primeiro"
          class="m-0 text-sm font-semibold text-n-slate-12"
        >
          {{ t('AGENTS.CAIXA_AGENTE_IA.CAMPO') }}
        </label>
        <ChoiceSelect
          :model-value="escolhido"
          trigger-id="quem-atende-primeiro"
          class="w-full max-w-md [&_button]:w-full"
          :options="opcoes"
          :aria-label="t('AGENTS.CAIXA_AGENTE_IA.CAMPO')"
          :placeholder="t('AGENTS.CAIXA_AGENTE_IA.ESCOLHER')"
          :disabled="trocando"
          @update:model-value="escolher"
        />
        <p
          v-if="recusa"
          data-recusa
          role="alert"
          class="m-0 flex items-start gap-2 rounded-xl bg-n-ruby-2 p-3 text-sm text-n-slate-12 ring-1 ring-inset ring-n-ruby-6"
        >
          <span
            class="i-lucide-circle-alert size-5 shrink-0 text-n-ruby-11"
            aria-hidden="true"
          />
          {{ recusa }}
        </p>
        <p
          v-else-if="pendente"
          data-troca
          aria-live="polite"
          class="m-0 flex items-start gap-2 rounded-xl bg-n-amber-2 p-3 text-sm text-n-slate-12 ring-1 ring-inset ring-n-amber-6"
        >
          <span
            class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ textoDaConfirmacao }}
        </p>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.CAIXA_AGENTE_IA.CAMPO_AJUDA') }}
        </p>
      </div>
      <div
        v-if="pendente"
        data-confirmacao
        class="flex flex-col-reverse gap-2 px-5 py-4 sm:flex-row sm:justify-end"
      >
        <AgenteBotao
          data-cancelar
          variante="contorno"
          tamanho="lg"
          :desabilitado="trocando"
          @click="cancelar"
        >
          {{ t('AGENTS.CAIXA_AGENTE_IA.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          v-if="!recusa"
          data-trocar
          tamanho="lg"
          :carregando="trocando"
          @click="trocar"
        >
          {{
            principal
              ? t('AGENTS.CAIXA_AGENTE_IA.TROCAR')
              : t('AGENTS.CAIXA_AGENTE_IA.CONFIRMAR')
          }}
        </AgenteBotao>
      </div>
    </section>
  </div>
</template>
