<script setup>
// #1593 — "Passar para…" na conversa: a pessoa que atende escolhe quem assume, entre as pessoas da caixa e os agentes
// de IA que atendem cliente e têm vínculo ativo nela. Uma frase confirma o que vai acontecer; a recusa do servidor
// aparece em linguagem simples. Sem a Fase 2 dos Agentes, só pessoas.
// Toda passagem guarda a origem (quem passou): com um agente de IA na conversa, o selo diz quem passou, o topo da
// lista oferece "Devolver para …" e, quando o cliente pede, a conversa volta para a origem.
// PROTÓTIPO: os agentes, a origem e a passagem para IA vêm do adaptador falso (dashboard/api/passarPara.js).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import {
  clientePedeVolta,
  comQuemEsta,
  ehAgente,
  passar,
  quemPodeReceber,
  simulando,
} from 'dashboard/api/passarPara';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const P = 'CRM_KANBAN.PASSAR_PARA';

const dialogRef = ref(null);
const carregando = ref(false);
const passando = ref(false);
const agentes = ref([]);
const origem = ref(null);
const semRobo = ref(false);
const escolhido = ref('');
const recusa = ref('');
// O agente de IA com a conversa e a origem; e o aviso de quando a conversa voltou para a origem.
const comIa = ref(null);
const voltou = ref(null);

const primeiroNome = nome => String(nome || '').split(' ')[0];
const conversaId = computed(() => props.conversation.id);
const inbox = computed(() =>
  store.getters['inboxes/getInbox'](props.conversation.inbox_id)
);
const eu = computed(() => store.getters.getCurrentUser);
const atribuida = computed(() => props.conversation.meta?.assignee || null);
const souEu = computed(() => atribuida.value?.id === eu.value?.id);

const lerComQuem = () => {
  comIa.value = comQuemEsta(conversaId.value);
};
watch(
  conversaId,
  () => {
    voltou.value = null;
    lerComQuem();
  },
  { immediate: true }
);

const nomeDoAgente = computed(() => comIa.value?.agente.name || '');
const devolver = computed(() =>
  comIa.value && origem.value
    ? {
        valor: origem.value.id,
        nome: primeiroNome(origem.value.name),
        devolver: true,
      }
    : null
);
const pessoas = computed(() =>
  store.getters['inboxAssignableAgents/getAssignableAgents'](
    props.conversation.inbox_id
  )
    .filter(pessoa => pessoa.id !== devolver.value?.valor)
    .map(pessoa => ({
      valor: pessoa.id,
      nome: pessoa.name,
      foto: pessoa.thumbnail,
      status: pessoa.availability_status,
      comEla: !comIa.value && atribuida.value?.id === pessoa.id,
      voce: pessoa.id === eu.value?.id,
    }))
);
const daIa = computed(() =>
  agentes.value.map(agente => ({
    valor: `ia:${agente.id}`,
    nome: agente.name,
    comEla: comIa.value?.agente.id === agente.id,
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
    const [, resposta] = await Promise.all([
      store.dispatch('inboxAssignableAgents/fetch', [
        props.conversation.inbox_id,
      ]),
      quemPodeReceber({
        conversaId: conversaId.value,
        caixa: inbox.value?.name,
      }),
    ]);
    agentes.value = resposta.agentes;
    origem.value = resposta.origem || null;
    semRobo.value = resposta.semRobo;
  } finally {
    carregando.value = false;
  }
};

const textoDaRecusa = erro =>
  erro?.motivo
    ? t(`${P}.RECUSA.${erro.motivo.toUpperCase()}`, erro.campos)
    : t(`${P}.RECUSA.ERRO`);

const atualizarAtribuida = assignee =>
  store.dispatch('setCurrentChatAssignee', {
    conversationId: conversaId.value,
    assignee,
  });

const confirmar = async () => {
  const destino = escolha.value;
  passando.value = true;
  recusa.value = '';
  try {
    const { assignee } = await passar({
      conversaId: conversaId.value,
      valor: destino.valor,
      por: { id: eu.value?.id, name: eu.value?.name },
    });
    atualizarAtribuida(assignee);
    voltou.value = null;
    lerComQuem();
    dialogRef.value?.close();
    useAlert(t(`${P}.PRONTO`, { nome: destino.nome }));
  } catch (erro) {
    recusa.value = textoDaRecusa(erro);
    escolhido.value = '';
  } finally {
    passando.value = false;
  }
};

// Só na demo (?demo=simular): imita o cliente pedindo para voltar a falar com quem passou.
const simularVolta = async () => {
  const resultado = await clientePedeVolta(conversaId.value);
  if (!resultado) return;
  atualizarAtribuida(resultado.assignee);
  voltou.value = {
    nome: primeiroNome(resultado.origem.name),
    agente: resultado.agente.name,
  };
  lerComQuem();
  useAlert(t(`${P}.VOLTOU`, voltou.value));
};
</script>

<template>
  <div class="flex min-w-0 items-center gap-2">
    <!-- No celular só cabe o essencial: o rosto de robô com o nome e o botão só com o ícone. -->
    <span
      v-if="comIa"
      data-com-ia
      :title="
        comIa.origem
          ? t(`${P}.COM_IA_POR`, {
              nome: comIa.agente.name,
              por: primeiroNome(comIa.origem.name),
            })
          : t(`${P}.COM_IA`, { nome: comIa.agente.name })
      "
      class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-n-iris-3 px-2 py-1 text-xs font-medium text-n-iris-11"
    >
      <span class="i-lucide-bot size-3.5 shrink-0" aria-hidden="true" />
      <span class="truncate sm:hidden">{{ comIa.agente.name }}</span>
      <span class="hidden truncate sm:inline">
        {{
          comIa.origem
            ? t(`${P}.COM_IA_POR`, {
                nome: comIa.agente.name,
                por: primeiroNome(comIa.origem.name),
              })
            : t(`${P}.COM_IA`, { nome: comIa.agente.name })
        }}
      </span>
    </span>
    <span
      v-else-if="voltou"
      data-voltou
      :title="t(`${P}.VOLTOU`, voltou)"
      class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-n-teal-3 px-2 py-1 text-xs font-medium text-n-teal-11"
    >
      <span class="i-lucide-undo-2 size-3.5 shrink-0" aria-hidden="true" />
      <span class="truncate sm:hidden">{{ voltou.nome }}</span>
      <span class="hidden truncate sm:inline">
        {{ t(`${P}.VOLTOU`, voltou) }}
      </span>
    </span>
    <!-- Controle só da demo, fora da tela de verdade: flutua no canto. -->
    <NextButton
      v-if="simulando() && comIa?.origem"
      type="button"
      icon="i-lucide-flask-conical"
      :label="t(`${P}.DEMO_PEDE_VOLTA`)"
      amber
      sm
      class="fixed bottom-28 start-4 z-50 shadow-lg"
      data-simular
      @click="simularVolta"
    />
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
            v-if="semRobo"
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
              ehAgente(escolha.valor) ? 'i-lucide-bot' : 'i-lucide-user-round'
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
