<script setup>
import { computed, ref, watch, nextTick, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmOpportunityContactPicker from './CrmOpportunityContactPicker.vue';
import CrmOpportunityRegistration from './CrmOpportunityRegistration.vue';
import { semDonosBarrados } from '../helpers/accessErrors';
import CampoValor from './card/campos/CampoValor.vue';
import CampoUrgencia from './card/campos/CampoUrgencia.vue';
import CampoFecharAte from './card/campos/CampoFecharAte.vue';
import { textosCom } from './card/textos';
import { useCardTipo } from './card/useCardTipo';
import {
  newRegistrationDraft,
  registrationPayload,
} from './opportunityRegistration';

const props = defineProps({
  pipelines: { type: Array, required: true },
  pipelineId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
  canCreateContact: { type: Boolean, default: false },
  initialContact: { type: Object, default: null },
  // #1423 — a gaveta mostra um passo por vez (1 = cliente, 2 = negócio).
  passo: { type: Number, default: 1, validator: v => [1, 2].includes(v) },
});
const emit = defineEmits(['save', 'passo']);
const { t, te } = useI18n();
// #1423 — as frases vêm de CRM_CARD.CRIAR.T; o que não estiver lá usa o texto
// de sempre.
const TEXTOS = 'CRM_CARD.CRIAR.T';
const label = textosCom({ t, te }, TEXTOS, 'CRM_KANBAN.OPPORTUNITY');
const C = 'CRM_CARD.CRIAR';
const formId = `crm-opportunity-${useId()}`;
const element = ref(null);
const mode = ref('existing');
const contact = ref(props.initialContact);
const registration = ref(null);
const registrationDraft = ref(newRegistrationDraft());
const registrationInitial = JSON.stringify(registrationDraft.value);
const validating = ref(false);
const more = ref(false);
const sending = ref(false);
const error = ref('');
const stageError = ref(false);
const stageRequest = useAbortableRequest();
const loadedStages = ref(props.stages);
const form = ref({
  title: '',
  pipelineId: props.pipelineId,
  stageId: props.stages[0]?.id || '',
  valueAmount: '',
  ownerId: '',
  currency: 'BRL',
  description: '',
  priority: 'medium',
  expectedCloseAt: '',
  score: 0,
  inboxId: '',
});
// #1498 — as palavras seguem o funil escolhido: Negócio (Vender), Assunto
// (Atender) e, na Cobrança, valor a receber e vencimento.
const funilEscolhido = computed(() =>
  props.pipelines.find(
    item => String(item.id) === String(form.value.pipelineId)
  )
);
const jeito = useCardTipo({ t, funil: funilEscolhido });
const N = chave => jeito.texto(`NEGOCIO.${chave}`);
const semValor = computed(() => jeito.atender.value && !jeito.cobranca.value);
const initial = JSON.stringify(form.value);
const dirty = computed(
  () =>
    (props.initialContact
      ? mode.value !== 'existing' ||
        contact.value?.id !== props.initialContact.id
      : Boolean(contact.value)) ||
    JSON.stringify(form.value) !== initial ||
    JSON.stringify(registrationDraft.value) !== registrationInitial
);
const pipelineOptions = computed(() =>
  props.pipelines.map(item => ({ value: item.id, label: item.name }))
);
const stageOptions = computed(() =>
  loadedStages.value.map(item => ({ value: item.id, label: item.name }))
);
// Acesso por funil (#1149): só aparece como dono quem tem o funil na caixa.
const donosBarrados = ref([]);
const ownerOptions = computed(() => [
  { value: '', label: t(`${C}.EU_CUIDO`) },
  ...semDonosBarrados(props.agents, donosBarrados.value).map(item => ({
    value: item.id,
    label: item.name,
  })),
]);
const inboxOptions = computed(() => [
  { value: '', label: t(`${C}.SEM_CAIXA`) },
  ...props.inboxes.map(item => ({ value: item.id, label: item.name })),
]);
const canSave = computed(
  () =>
    props.canManage &&
    !sending.value &&
    !validating.value &&
    !stageRequest.isPending.value &&
    !stageError.value &&
    Boolean(form.value.title.trim()) &&
    pipelineOptions.value.some(
      item => String(item.value) === String(form.value.pipelineId)
    ) &&
    stageOptions.value.some(
      item => String(item.value) === String(form.value.stageId)
    ) &&
    (mode.value === 'none' ||
      (mode.value === 'new'
        ? props.canCreateContact && registration.value?.canSave
        : Boolean(contact.value?.id)))
);
// #1423 — o passo 1 (quem é o cliente) está resolvido.
const relacaoPronta = computed(
  () =>
    mode.value === 'none' ||
    (mode.value === 'new'
      ? props.canCreateContact && Boolean(registration.value?.canSave)
      : Boolean(contact.value?.id))
);
// #1423 — o rodapé da gaveta diz com quem o cliente entra no funil.
const summary = computed(() => {
  if (mode.value === 'none') return t(`${C}.RESUMO_SEM`);
  const nome =
    mode.value === 'new'
      ? registrationDraft.value.name.trim()
      : contact.value?.name || '';
  return nome
    ? t(`${C}.RESUMO_COM`, { nome })
    : t(`${C}.RESUMO_${mode.value === 'new' ? 'NOVA' : 'ESCOLHER'}`);
});
// O aviso de nome vazio só aparece depois que a pessoa mexe no campo ou
// tenta criar.
const tentou = ref(false);
const mexeuNoNome = ref(false);
const faltaNome = computed(
  () => (tentou.value || mexeuNoNome.value) && !form.value.title.trim()
);
const opcoesDaPessoa = computed(() => [
  { valor: 'existing', chave: 'EXISTENTE', icone: 'i-lucide-book-user' },
  {
    valor: 'new',
    chave: 'NOVA',
    icone: 'i-lucide-user-plus',
    desligada: !props.canCreateContact,
  },
  { valor: 'none', chave: 'SEM', icone: 'i-lucide-user-x' },
]);
const loadStages = async () => {
  stageError.value = false;
  loadedStages.value = [];
  form.value.stageId = '';
  try {
    const response = await stageRequest.run(() =>
      CrmKanbanAPI.getStages(form.value.pipelineId)
    );
    if (!response) return;
    loadedStages.value = response.data.payload;
    form.value.stageId = loadedStages.value[0]?.id || '';
  } catch {
    stageError.value = true;
  }
};
watch(() => form.value.pipelineId, loadStages, { flush: 'sync' });

// Só vale a resposta da última troca de funil ou caixa.
let ultimaConsultaDeDonos = 0;
const carregarDonosBarrados = async () => {
  ultimaConsultaDeDonos += 1;
  const consulta = ultimaConsultaDeDonos;
  const { pipelineId, inboxId } = form.value;
  let barrados = [];
  if (pipelineId && inboxId) {
    try {
      const { data } = await CrmKanbanAPI.getOwnerOptions({
        pipelineId,
        inboxId,
      });
      barrados = data.payload.blocked || [];
    } catch {
      // Sem a lista, o servidor ainda recusa o dono sem o funil e a tela avisa.
    }
  }
  if (consulta !== ultimaConsultaDeDonos) return;
  donosBarrados.value = barrados;
  if (barrados.includes(Number(form.value.ownerId))) {
    form.value.ownerId = '';
    useAlert(t('CRM_KANBAN.ACCESS.OWNER_WITHOUT_FUNNEL'));
  }
};
watch(() => [form.value.pipelineId, form.value.inboxId], carregarDonosBarrados);
watch(
  () => props.stages,
  stages => {
    if (String(form.value.pipelineId) !== String(props.pipelineId)) return;
    loadedStages.value = stages;
    if (!stages.some(item => item.id === form.value.stageId))
      form.value.stageId = '';
  }
);
const changeMode = next => {
  if (
    sending.value ||
    validating.value ||
    (next === 'new' && !props.canCreateContact)
  )
    return;
  mode.value = next;
  contact.value = null;
  error.value = '';
};
const useExistingContact = person => {
  changeMode('existing');
  contact.value = person;
};
let requestKey = crypto.randomUUID();
let submitted = '';
const submit = async () => {
  tentou.value = true;
  if (!canSave.value) return;
  if (mode.value === 'new') {
    validating.value = true;
    let valid;
    try {
      valid = await registration.value.validate();
    } finally {
      validating.value = false;
    }
    if (!valid || !canSave.value) {
      if (!valid) emit('passo', 1);
      return;
    }
  }
  if (element.value.querySelector(':invalid')) {
    more.value = true;
    await nextTick();
    element.value.reportValidity();
    return;
  }
  const data = form.value;
  const payload = {
    title: data.title.trim(),
    description: data.description.trim(),
    pipeline_id: data.pipelineId,
    stage_id: data.stageId,
    // #1498 — Atender (fora a Cobrança) não leva valor, nota nem data, mesmo
    // que algo tenha sido digitado antes de trocar o funil.
    value_cents: semValor.value
      ? 0
      : Math.round(Number(data.valueAmount || 0) * 100),
    currency: data.currency.trim() || 'BRL',
    priority: data.priority,
    score: jeito.atender.value ? 0 : Number(data.score || 0),
    expected_close_at: semValor.value ? null : data.expectedCloseAt || null,
    ...(data.ownerId ? { owner_id: data.ownerId } : {}),
    ...(data.inboxId ? { inbox_id: data.inboxId } : {}),
    ...(mode.value === 'new'
      ? { relationship: registrationPayload(registrationDraft.value) }
      : {}),
    ...(mode.value === 'existing' && contact.value
      ? { contact_id: contact.value.id }
      : {}),
  };
  const fingerprint = JSON.stringify(payload);
  if (submitted && fingerprint !== submitted) requestKey = crypto.randomUUID();
  submitted = fingerprint;
  sending.value = true;
  error.value = '';
  emit('save', { ...payload, idempotencyKey: requestKey }, failure => {
    sending.value = false;
    const detail = failure?.response?.data?.error;
    if (
      mode.value === 'new' &&
      ['contact', 'company'].includes(detail?.section)
    ) {
      emit('passo', 1);
      registration.value?.showError(detail);
      return;
    }
    if (detail?.section === 'opportunity') more.value = true;
    error.value = label('SAVE_ERROR');
  });
};
defineExpose({
  relacaoPronta,
  // #1423 — a prévia "Onde vai entrar" segue o funil e a etapa escolhidos.
  escolha: computed(() => ({
    funilId: form.value.pipelineId,
    etapaId: form.value.stageId,
    etapas: loadedStages.value,
  })),
  dirty,
  sending: computed(() => sending.value || validating.value),
  canSave,
  formId,
  summary,
});
</script>

<template>
  <form
    :id="formId"
    ref="element"
    class="grid min-w-0 gap-6"
    data-crm-opportunity-form
    novalidate
    @submit.prevent="submit"
  >
    <div
      v-if="error"
      role="alert"
      class="rounded-xl bg-n-ruby-3 p-4 text-sm leading-6 text-n-ruby-11"
    >
      {{ error }}
    </div>
    <fieldset :disabled="sending" class="m-0 grid min-w-0 gap-6 border-0 p-0">
      <section
        v-show="passo === 1"
        class="grid min-w-0 gap-4"
        data-opportunity-relationship
      >
        <!-- #1423 — passo 1: três escolhas grandes, uma frase cada. -->
        <div
          class="grid gap-2 sm:grid-cols-3"
          role="group"
          :aria-label="t(`${C}.TITULO_1`)"
          data-criar-pessoa
        >
          <button
            v-for="opcao in opcoesDaPessoa"
            :key="opcao.valor"
            type="button"
            :data-pessoa="opcao.valor"
            :aria-pressed="mode === opcao.valor"
            :disabled="sending || opcao.desligada"
            class="flex min-h-11 flex-col items-start gap-1.5 rounded-2xl p-4 text-start ring-1 ring-inset transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed disabled:opacity-60"
            :class="
              mode === opcao.valor
                ? 'bg-n-blue-2 ring-2 ring-n-blue-8'
                : 'bg-n-solid-1 ring-n-weak hover:ring-n-slate-7'
            "
            @click="changeMode(opcao.valor)"
          >
            <span
              class="size-5 text-n-blue-11"
              :class="opcao.icone"
              aria-hidden="true"
            />
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${C}.PESSOA.${opcao.chave}.TITULO`) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{
                opcao.desligada
                  ? t(`${C}.PESSOA.NOVA.SEM_PERMISSAO`)
                  : t(`${C}.PESSOA.${opcao.chave}.TEXTO`)
              }}
            </span>
          </button>
        </div>
        <p
          v-if="mode === 'none'"
          class="mb-0 flex items-start gap-3 rounded-2xl bg-n-alpha-2 p-4 text-[0.9375rem] text-n-slate-12"
          data-opportunity-unlinked
        >
          <span
            class="i-lucide-info mt-0.5 size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t(`${C}.PESSOA.SEM.DEPOIS`) }}
        </p>
        <CrmOpportunityRegistration
          v-else-if="mode === 'new'"
          ref="registration"
          v-model="registrationDraft"
          :textos="`${TEXTOS}.REGISTRATION`"
          :disabled="sending || !canCreateContact"
          @use-contact="useExistingContact"
        />
        <CrmOpportunityContactPicker
          v-else
          v-model="contact"
          :textos="TEXTOS"
          :disabled="sending"
        />
      </section>
      <section
        v-show="passo === 2"
        class="grid min-w-0 gap-5"
        data-opportunity-details
      >
        <!-- #1423 — passo 2: as palavras e os campos do Negócio. -->
        <Input
          v-model="form.title"
          required
          data-negocio-titulo
          custom-input-class="!text-base"
          :label="N('NOME')"
          :placeholder="N('TITULO_EXEMPLO')"
          :message="faltaNome ? N('TITULO_FALTA') : ''"
          :message-type="faltaNome ? 'error' : 'info'"
          :disabled="sending"
          @update:model-value="mexeuNoNome = true"
        />
        <div class="grid min-w-0 grid-cols-1 gap-4 min-[440px]:grid-cols-2">
          <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
            <span class="font-medium">{{ t(`${C}.FUNIL`) }}</span>
            <ChoiceSelect
              v-model="form.pipelineId"
              :options="pipelineOptions"
              :aria-label="t(`${C}.FUNIL`)"
              :disabled="sending"
            />
          </label>
          <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
            <span class="font-medium">{{ t(`${C}.ETAPA`) }}</span>
            <ChoiceSelect
              v-model="form.stageId"
              :options="stageOptions"
              :aria-label="t(`${C}.ETAPA`)"
              :placeholder="
                label(
                  stageRequest.isPending.value
                    ? 'LOADING_STAGES'
                    : 'SELECT_STAGE'
                )
              "
              :disabled="sending || stageRequest.isPending.value"
            />
          </label>
        </div>
        <div
          v-if="stageError"
          role="alert"
          class="flex flex-wrap items-center gap-2 text-sm text-n-ruby-11"
        >
          <span>{{ label('STAGE_ERROR') }}</span>
          <Button
            type="button"
            ghost
            class="!min-h-11"
            :label="label('RETRY')"
            :disabled="sending"
            @click="loadStages"
          />
        </div>
        <CampoValor
          v-if="!semValor"
          v-model:valor="form.valueAmount"
          v-model:moeda="form.currency"
          :rotulo="N('VALOR')"
          :somente-leitura="sending"
        />
        <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
          <span class="font-medium">{{ t(`${C}.QUEM_CUIDA`) }}</span>
          <ChoiceSelect
            v-model="form.ownerId"
            :options="ownerOptions"
            :aria-label="t(`${C}.QUEM_CUIDA`)"
            :disabled="sending || !canManage"
          />
          <span class="text-sm text-n-slate-11">
            {{ t(`${C}.QUEM_CUIDA_DICA`) }}
          </span>
        </label>
        <details
          class="group rounded-2xl border border-n-weak bg-n-solid-1"
          :open="more"
          @toggle="more = $event.currentTarget.open"
        >
          <summary
            class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
          >
            {{ t('CRM_CARD.NEGOCIO.MAIS') }}
            <span
              class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
              aria-hidden="true"
            />
          </summary>
          <div
            :id="`${formId}-options`"
            class="flex flex-col gap-5 border-t border-n-weak p-4"
          >
            <TextArea
              :id="`${formId}-description`"
              v-model="form.description"
              :label="N('OBSERVACOES')"
              :placeholder="N('OBSERVACOES_EXEMPLO')"
              :disabled="sending"
              auto-height
            />
            <CampoUrgencia
              v-model="form.priority"
              :rotulo="N('URGENCIA')"
              :somente-leitura="sending"
            />
            <Input
              v-if="!jeito.atender.value"
              v-model="form.score"
              type="number"
              min="0"
              max="100"
              step="1"
              class="max-w-[22rem]"
              :label="t('CRM_CARD.NEGOCIO.ATENCAO')"
              :message="t('CRM_CARD.NEGOCIO.ATENCAO_DICA')"
              :disabled="sending"
            />
            <CampoFecharAte
              v-if="!semValor"
              v-model="form.expectedCloseAt"
              :rotulo="N('FECHAR_ATE')"
              :somente-leitura="sending"
            />
            <label
              v-if="inboxes.length"
              class="grid min-w-0 gap-2 text-sm text-n-slate-12"
            >
              <span class="font-medium">{{ t(`${C}.CAIXA`) }}</span>
              <ChoiceSelect
                v-model="form.inboxId"
                :options="inboxOptions"
                :aria-label="t(`${C}.CAIXA`)"
                :disabled="sending"
              />
              <span class="text-sm text-n-slate-11">
                {{ t(`${C}.CAIXA_DICA`) }}
              </span>
            </label>
          </div>
        </details>
      </section>
    </fieldset>
  </form>
</template>
