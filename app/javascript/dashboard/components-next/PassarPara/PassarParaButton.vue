<script setup>
// #1593 — "Passar para…" na conversa: quem atende escolhe quem assume, entre as pessoas da caixa e os agentes de IA
// que podem receber nela (regra dos Agentes, com a Fase 2). Uma frase confirma o que vai acontecer; a recusa do
// servidor aparece em linguagem simples. Sem a Fase 2, só pessoas.
// Com um agente de IA na conversa, o selo diz com quem ela está e quem passou (a origem, do registro de passagens do
// CRM), e o topo da lista oferece "Devolver para …".
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import PassarParaAPI from 'dashboard/api/passarPara';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const P = 'CRM_KANBAN.PASSAR_PARA';
const PREFIXO_IA = 'ia:';
const DEVOLVER = 'devolver';
// Códigos que o servidor devolve e a tela explica (Crm::PassarPara e Autonomia::Agents::PassarParaIa).
const RECUSAS = [
  'fase2_desligada',
  'nao_atende_cliente',
  'sem_vinculo_na_caixa',
  'outra_conta',
  'conversa_resolvida',
  'pessoa_atribuida',
  'pessoa_fora_da_caixa',
  'destino_invalido',
];

const dialogRef = ref(null);
const carregando = ref(false);
const passando = ref(false);
// O que o servidor diz da conversa: { fase2, sem_robo, agentes, com_ia, origem }.
const retrato = ref(null);
const escolhido = ref('');
const recusa = ref('');

const primeiroNome = nome => String(nome || '').split(' ')[0];
const conversaId = computed(() => props.conversation.id);
const eu = computed(() => store.getters.getCurrentUser);
const atribuida = computed(() => props.conversation.meta?.assignee || null);
const comRobo = computed(
  () => props.conversation.meta?.assignee_type === 'AgentBot'
);
const souEu = computed(
  () => !comRobo.value && atribuida.value?.id === eu.value?.id
);

const lerRetrato = async () => {
  const pedido = conversaId.value;
  try {
    const { data } = await PassarParaAPI.quemPodeReceber(pedido);
    if (pedido === conversaId.value) retrato.value = data;
  } catch {
    if (pedido === conversaId.value) retrato.value = null;
  }
};

// O selo só existe com um robô no nome da conversa: aí vale perguntar ao servidor qual agente e quem passou.
watch(
  conversaId,
  () => {
    retrato.value = null;
    if (comRobo.value) lerRetrato();
  },
  { immediate: true }
);
watch(comRobo, comBot => {
  if (comBot) lerRetrato();
  else retrato.value = null;
});

const comIa = computed(() => retrato.value?.com_ia || null);
const origem = computed(() => (comIa.value && retrato.value?.origem) || null);
const nomeDoAgente = computed(() => comIa.value?.name || '');
// O selo: com quem está e quem passou. Robô de outro sistema (n8n, Zapier…) aparece como "agente externo".
const selo = computed(() => {
  if (!comIa.value) return '';
  if (!origem.value) return t(`${P}.COM_IA`, { nome: comIa.value.name });
  const externo = origem.value.classe === 'AgentBot';
  return t(externo ? `${P}.COM_IA_POR_EXTERNO` : `${P}.COM_IA_POR`, {
    nome: comIa.value.name,
    por: externo ? origem.value.name : primeiroNome(origem.value.name),
  });
});
const devolver = computed(() =>
  origem.value?.pode_receber
    ? {
        valor: DEVOLVER,
        id: origem.value.id,
        nome: primeiroNome(origem.value.name),
        devolver: true,
      }
    : null
);
const pessoas = computed(() =>
  store.getters['inboxAssignableAgents/getAssignableAgents'](
    props.conversation.inbox_id
  )
    .filter(pessoa => pessoa.id !== devolver.value?.id)
    .map(pessoa => ({
      valor: String(pessoa.id),
      id: pessoa.id,
      tipo: 'pessoa',
      nome: pessoa.name,
      foto: pessoa.thumbnail,
      status: pessoa.availability_status,
      comEla: !comRobo.value && atribuida.value?.id === pessoa.id,
      voce: pessoa.id === eu.value?.id,
    }))
);
const daIa = computed(() =>
  (retrato.value?.agentes || []).map(agente => ({
    valor: `${PREFIXO_IA}${agente.id}`,
    id: agente.id,
    tipo: 'ia',
    nome: agente.name,
    comEla: agente.com_a_conversa,
  }))
);
const todos = computed(() => [
  ...(devolver.value ? [devolver.value] : []),
  ...pessoas.value,
  ...daIa.value,
]);
const escolha = computed(
  () => todos.value.find(item => item.valor === escolhido.value) || null
);
const ninguem = computed(() => !todos.value.some(item => !item.comEla));
const confirmacao = computed(() => {
  const destino = escolha.value;
  if (!destino) return '';
  if (destino.devolver) {
    return t(`${P}.CONFIRMA_DEVOLVE`, {
      nome: destino.nome,
      agente: nomeDoAgente.value,
    });
  }
  if (souEu.value) return t(`${P}.CONFIRMA_SAI`, { nome: destino.nome });
  if (comIa.value) {
    return t(`${P}.CONFIRMA_NO_LUGAR`, {
      nome: destino.nome,
      agente: nomeDoAgente.value,
    });
  }
  return t(`${P}.CONFIRMA`, { nome: destino.nome });
});

const abrir = async () => {
  escolhido.value = '';
  recusa.value = '';
  dialogRef.value?.open();
  carregando.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxAssignableAgents/fetch', [
        props.conversation.inbox_id,
      ]),
      lerRetrato(),
    ]);
  } finally {
    carregando.value = false;
  }
};

const textoDaRecusa = codigo => {
  const conhecido = RECUSAS.includes(codigo) ? codigo : 'erro';
  return t(`${P}.RECUSA.${conhecido.toUpperCase()}`, {
    nome: escolha.value?.nome || '',
  });
};

// Quem assumiu entra na conversa da lista na hora: a pessoa, ou o robô do agente de IA (o cabeçalho e o selo mudam
// sem esperar o aviso do servidor).
const atualizarConversa = (conversationId, data) => {
  if (data.assignee) {
    store.dispatch('setCurrentChatAssignee', {
      conversationId,
      assignee: data.assignee,
    });
  } else if (data.com_ia) {
    store.dispatch('setCurrentChatAssignee', {
      conversationId,
      assignee: { id: data.com_ia.bot_id, name: data.com_ia.name },
      assigneeType: 'AgentBot',
    });
  }
};

const confirmar = async () => {
  const destino = escolha.value;
  // A pessoa pode trocar de conversa enquanto o pedido está em voo: a resposta vale só para a conversa pedida.
  const pedido = conversaId.value;
  passando.value = true;
  recusa.value = '';
  try {
    const { data } = await PassarParaAPI.passar(pedido, {
      tipo: destino.devolver ? 'pessoa' : destino.tipo,
      id: destino.id,
    });
    atualizarConversa(pedido, data);
    if (pedido !== conversaId.value) return;
    retrato.value = data;
    dialogRef.value?.close();
    useAlert(t(`${P}.PRONTO`, { nome: destino.nome }));
  } catch (erro) {
    if (pedido !== conversaId.value) return;
    recusa.value = textoDaRecusa(erro?.response?.data?.codigo);
    escolhido.value = '';
    // A lista se atualiza: quem parou ou saiu da caixa deixa de aparecer.
    lerRetrato();
  } finally {
    passando.value = false;
  }
};
</script>

<template>
  <div class="flex min-w-0 items-center gap-2">
    <!-- No celular só cabe o essencial: o rosto de robô com o nome e o botão só com o ícone. -->
    <span
      v-if="comIa"
      data-com-ia
      :title="selo"
      class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-n-iris-3 px-2 py-1 text-xs font-medium text-n-iris-11"
    >
      <span class="i-lucide-bot size-3.5 shrink-0" aria-hidden="true" />
      <span class="truncate sm:hidden">{{ comIa.name }}</span>
      <span class="hidden truncate sm:inline">{{ selo }}</span>
    </span>
    <span class="sm:hidden">
      <NextButton
        type="button"
        icon="i-lucide-arrow-right-left"
        :aria-label="t(`${P}.BOTAO`)"
        :title="t(`${P}.BOTAO`)"
        aria-haspopup="dialog"
        slate
        faded
        sm
        class="relative before:absolute before:-inset-1.5"
        data-passar-para-celular
        @click="abrir"
      />
    </span>
    <span class="hidden sm:contents">
      <NextButton
        type="button"
        icon="i-lucide-arrow-right-left"
        :label="t(`${P}.BOTAO`)"
        aria-haspopup="dialog"
        slate
        faded
        sm
        class="relative before:absolute before:inset-x-0 before:-inset-y-1.5"
        data-passar-para
        @click="abrir"
      />
    </span>

    <Dialog
      ref="dialogRef"
      :title="t(`${P}.TITULO`)"
      :description="t(`${P}.DESCRICAO`)"
      :show-cancel-button="false"
      :show-confirm-button="false"
      width="md"
    >
      <div
        v-if="carregando"
        role="status"
        class="py-6 text-center text-sm text-n-slate-11"
      >
        {{ t(`${P}.CARREGANDO`) }}
      </div>

      <div v-else class="flex flex-col gap-4">
        <p
          v-if="recusa"
          role="alert"
          data-recusa
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-ruby-2 px-3 py-3 text-sm leading-5 text-n-ruby-11"
        >
          <span
            class="i-lucide-circle-alert mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ recusa }}
        </p>

        <label
          v-if="devolver"
          data-devolver
          class="flex min-h-11 cursor-pointer items-center gap-3 rounded-xl border-2 px-3 py-3 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
          :class="
            escolhido === devolver.valor
              ? 'border-n-blue-8 bg-n-blue-2'
              : 'border-n-teal-7 bg-n-teal-2 hover:border-n-teal-9'
          "
        >
          <input
            v-model="escolhido"
            type="radio"
            name="passar-para"
            class="sr-only"
            :value="devolver.valor"
          />
          <span
            class="grid size-8 shrink-0 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
            aria-hidden="true"
          >
            <span class="i-lucide-undo-2 size-4" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ t(`${P}.DEVOLVER`, { nome: devolver.nome }) }}
            </span>
            <span class="text-xs leading-4 text-n-slate-11">
              {{
                t(`${P}.DEVOLVER_DESC`, {
                  nome: devolver.nome,
                  agente: nomeDoAgente,
                })
              }}
            </span>
          </span>
        </label>

        <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
          <legend class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ t(`${P}.PESSOAS`) }}
          </legend>
          <label
            v-for="item in pessoas"
            :key="item.valor"
            data-opcao-pessoa
            class="flex min-h-11 items-center gap-3 rounded-xl border px-3 py-2 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
            :class="[
              escolhido === item.valor
                ? 'border-n-blue-8 bg-n-blue-2'
                : 'border-n-weak',
              item.comEla
                ? 'cursor-default opacity-60'
                : 'cursor-pointer hover:border-n-slate-7',
            ]"
          >
            <input
              v-model="escolhido"
              type="radio"
              name="passar-para"
              class="sr-only"
              :value="item.valor"
              :disabled="item.comEla"
            />
            <Avatar
              :name="item.nome"
              :src="item.foto"
              :size="32"
              :status="item.status"
            />
            <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
              {{ item.voce ? t(`${P}.VOCE`, { nome: item.nome }) : item.nome }}
            </span>
            <span v-if="item.comEla" class="text-xs text-n-slate-11">
              {{ t(`${P}.COM_A_CONVERSA`) }}
            </span>
          </label>
        </fieldset>

        <fieldset
          v-if="daIa.length"
          class="m-0 flex flex-col gap-2 border-0 p-0"
        >
          <legend class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ t(`${P}.AGENTES`) }}
          </legend>
          <label
            v-for="item in daIa"
            :key="item.valor"
            data-opcao-ia
            class="flex min-h-11 items-center gap-3 rounded-xl border px-3 py-2 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
            :class="[
              escolhido === item.valor
                ? 'border-n-blue-8 bg-n-blue-2'
                : 'border-n-weak',
              item.comEla
                ? 'cursor-default opacity-60'
                : 'cursor-pointer hover:border-n-slate-7',
            ]"
          >
            <input
              v-model="escolhido"
              type="radio"
              name="passar-para"
              class="sr-only"
              :value="item.valor"
              :disabled="item.comEla"
            />
            <span
              class="grid size-8 shrink-0 place-items-center rounded-full bg-n-iris-3 text-n-iris-11"
              aria-hidden="true"
            >
              <span class="i-lucide-bot size-4" />
            </span>
            <span
              class="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1"
            >
              <span class="truncate text-sm text-n-slate-12">
                {{ item.nome }}
              </span>
              <span
                class="rounded-md bg-n-iris-3 px-1.5 py-0.5 text-xs font-medium text-n-iris-11"
              >
                {{ t('CRM_CAIXAS.PESSOAS.SELO_IA') }}
              </span>
            </span>
            <span v-if="item.comEla" class="text-xs text-n-slate-11">
              {{ t(`${P}.COM_A_CONVERSA`) }}
            </span>
          </label>
          <p
            v-if="retrato?.sem_robo"
            data-sem-robo
            class="mb-0 flex items-start gap-2 text-xs leading-4 text-n-slate-11"
          >
            <span
              class="i-lucide-info mt-px size-3.5 shrink-0"
              aria-hidden="true"
            />
            {{ t(`${P}.SEM_ROBO`) }}
          </p>
        </fieldset>

        <p v-if="ninguem" class="mb-0 text-sm text-n-amber-11">
          {{ t(`${P}.NINGUEM`) }}
        </p>

        <div
          v-if="escolha"
          data-confirmacao
          class="flex items-start gap-2 rounded-xl bg-n-alpha-2 px-3 py-3 text-[0.9375rem] leading-6 text-n-slate-12"
        >
          <span
            class="mt-1 size-4 shrink-0 text-n-slate-11"
            :class="
              escolha.tipo === 'ia' ? 'i-lucide-bot' : 'i-lucide-user-round'
            "
            aria-hidden="true"
          />
          {{ confirmacao }}
        </div>
      </div>

      <template #footer>
        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <NextButton
            type="button"
            slate
            faded
            class="min-h-11 w-full sm:w-auto"
            :label="t(`${P}.CANCELAR`)"
            @click="dialogRef?.close()"
          />
          <NextButton
            type="button"
            class="min-h-11 w-full sm:w-auto"
            :icon="
              escolha?.devolver
                ? 'i-lucide-undo-2'
                : 'i-lucide-arrow-right-left'
            "
            :label="
              escolha
                ? t(escolha.devolver ? `${P}.DEVOLVER` : `${P}.PASSAR_PARA`, {
                    nome: escolha.nome,
                  })
                : t(`${P}.ESCOLHA`)
            "
            :disabled="!escolha || passando"
            :is-loading="passando"
            data-confirmar
            @click="confirmar"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
