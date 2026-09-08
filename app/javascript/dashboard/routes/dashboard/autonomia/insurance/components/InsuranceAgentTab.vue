<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AutonomiaInsuranceAPI from 'dashboard/api/autonomiaInsurance';

// Aba Agente (PRD §18-19). Até 08/09/2026 era um CARTAZ: o botão "Criar Agente de Cotação" apenas
// navegava para o construtor conversacional, e quem clicasse saía de lá com um agente `custom` sem
// ferramenta de cotação nenhuma — igual a qualquer outro, e sem saber cotar.
//
// Agora ela cria de verdade. O agente nasce com a instrução que a Autonom.ia mantém, o especialista
// de auto e a ferramenta de cotação já ligados; a corretora responde quatro perguntas e nada mais.
// A montagem inteira mora no backend (`Insurance::QuoteAgent::Builder`), porque um agente montado a
// partir do que a tela mandar seria diferente a cada versão do frontend.
const { t } = useI18n();
const router = useRouter();

const BEHAVIORS = ['consultivo', 'objetivo'];
const PILLARS = ['COLLECT', 'QUOTE', 'EXPLAIN', 'HANDOFF'];

const agent = ref(null);
const loading = ref(true);
const saving = ref(false);
const showForm = ref(false);
const errorKey = ref('');

const form = ref({
  name: '',
  brokerName: '',
  businessHours: '',
  behavior: 'consultivo',
});

// O botão só habilita com os dois nomes preenchidos — o backend recusa vazio, e deixar o clique
// disponível para receber um erro previsível é atrito sem causa.
const canSubmit = computed(
  () => form.value.name.trim() !== '' && form.value.brokerName.trim() !== ''
);

const branchNames = computed(() =>
  (agent.value?.specialists || []).map(s => s.name).join(', ')
);

const load = async () => {
  try {
    const { data } = await AutonomiaInsuranceAPI.getQuoteAgent();
    agent.value = data.payload;
  } catch (e) {
    agent.value = null;
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const openForm = () => {
  errorKey.value = '';
  showForm.value = true;
};

// O erro vira mensagem por CÓDIGO, não pelo texto que o backend mandou: o `detail` diz qual campo
// está errado e serve no log, mas a tela fala a língua do produto.
const messageFor = error => {
  const code = error?.response?.data?.error;
  if (code === 'nome_invalido') return 'NOME_INVALIDO';
  if (code === 'comportamento_invalido') return 'COMPORTAMENTO_INVALIDO';
  return 'GENERIC';
};

const submit = async () => {
  if (!canSubmit.value || saving.value) return;
  saving.value = true;
  errorKey.value = '';
  try {
    const { data } = await AutonomiaInsuranceAPI.createQuoteAgent(form.value);
    agent.value = data.payload;
    showForm.value = false;
  } catch (error) {
    // 409 não é falha: já existe um, e a tela mostra o que existe em vez de um erro sobre algo que
    // ela mesma pediu.
    if (error?.response?.status === 409) {
      agent.value = error.response.data?.payload || null;
      showForm.value = false;
    } else {
      errorKey.value = messageFor(error);
    }
  } finally {
    saving.value = false;
  }
};

const goToAgents = () => {
  router.push({ name: 'autonomia_agents_index' });
};
</script>

<template>
  <div class="flex flex-col gap-6 max-w-3xl">
    <section class="rounded-xl border border-n-weak bg-n-solid-1 px-5 py-5">
      <div class="flex items-start gap-4">
        <span
          class="flex items-center justify-center rounded-lg shrink-0 size-10 bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-bot size-5" />
        </span>
        <div class="flex flex-col gap-2 min-w-0">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.AGENT.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('INSURANCE.AGENT.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <ul class="grid gap-3 mt-5 sm:grid-cols-2">
        <li
          v-for="key in PILLARS"
          :key="key"
          class="flex items-start gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 text-sm"
        >
          <span class="i-lucide-check size-4 mt-0.5 text-n-teal-11 shrink-0" />
          <span class="text-n-slate-12">
            {{ t(`INSURANCE.AGENT.PILLARS.${key}`) }}
          </span>
        </li>
      </ul>

      <p class="mt-5 text-xs text-n-slate-11">
        {{ t('INSURANCE.AGENT.LOCKED_NOTE') }}
      </p>

      <!-- Já existe: um por conta, e a tela mostra qual é em vez de oferecer criar de novo. -->
      <div
        v-if="!loading && agent"
        class="flex flex-col gap-2 mt-5 px-4 py-3 rounded-lg bg-n-teal-2 border border-n-teal-5"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-circle-check size-4 text-n-teal-11 shrink-0" />
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.AGENT.EXISTING.TITLE') }} — {{ agent.name }}
          </span>
        </div>
        <p v-if="branchNames" class="text-sm text-n-slate-11">
          {{ t('INSURANCE.AGENT.EXISTING.BRANCHES', { ramos: branchNames }) }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t('INSURANCE.AGENT.EXISTING.NOTE') }}
        </p>
      </div>

      <div
        v-if="!loading && !showForm"
        class="flex flex-wrap items-center gap-2 mt-5"
      >
        <NextButton
          v-if="!agent"
          solid
          blue
          icon="i-lucide-sparkles"
          :label="t('INSURANCE.AGENT.ACTIONS.CONFIGURE')"
          @click="openForm"
        />
        <NextButton
          v-else
          solid
          blue
          icon="i-lucide-external-link"
          :label="t('INSURANCE.AGENT.ACTIONS.OPEN_AGENT')"
          @click="goToAgents"
        />
        <NextButton
          faded
          slate
          icon="i-lucide-list"
          :label="t('INSURANCE.AGENT.ACTIONS.OPEN_AGENTS')"
          @click="goToAgents"
        />
      </div>
    </section>

    <!-- As quatro perguntas. Tudo o mais vem pronto do backend. -->
    <section
      v-if="showForm"
      class="rounded-xl border border-n-weak bg-n-solid-1 px-5 py-5 flex flex-col gap-5"
    >
      <div class="flex flex-col gap-1">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('INSURANCE.AGENT.FORM.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('INSURANCE.AGENT.FORM.SUBTITLE') }}
        </p>
      </div>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INSURANCE.AGENT.FORM.NAME_LABEL') }}
        </span>
        <input
          v-model="form.name"
          type="text"
          maxlength="120"
          :placeholder="t('INSURANCE.AGENT.FORM.NAME_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('INSURANCE.AGENT.FORM.NAME_HINT') }}
        </span>
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INSURANCE.AGENT.FORM.BROKER_LABEL') }}
        </span>
        <input
          v-model="form.brokerName"
          type="text"
          maxlength="120"
          :placeholder="t('INSURANCE.AGENT.FORM.BROKER_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('INSURANCE.AGENT.FORM.BROKER_HINT') }}
        </span>
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INSURANCE.AGENT.FORM.HOURS_LABEL') }}
        </span>
        <input
          v-model="form.businessHours"
          type="text"
          maxlength="120"
          :placeholder="t('INSURANCE.AGENT.FORM.HOURS_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('INSURANCE.AGENT.FORM.HOURS_HINT') }}
        </span>
      </label>

      <!-- Botão de escolha, e não texto livre: o comportamento é uma de duas, e escrever livre aqui
           produziria instrução que a Autonom.ia não sabe interpretar. -->
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INSURANCE.AGENT.FORM.BEHAVIOR_LABEL') }}
        </span>
        <div class="grid gap-2 sm:grid-cols-2">
          <button
            v-for="value in BEHAVIORS"
            :key="value"
            type="button"
            :aria-pressed="form.behavior === value"
            class="flex flex-col gap-1 px-3 py-2 text-left rounded-lg border transition-colors"
            :class="
              form.behavior === value
                ? 'border-n-brand bg-n-alpha-2'
                : 'border-n-weak bg-n-solid-2 hover:border-n-strong'
            "
            @click="form.behavior = value"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`INSURANCE.AGENT.FORM.BEHAVIOR_${value.toUpperCase()}`) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                t(`INSURANCE.AGENT.FORM.BEHAVIOR_${value.toUpperCase()}_HINT`)
              }}
            </span>
          </button>
        </div>
        <span class="text-xs text-n-slate-11">
          {{ t('INSURANCE.AGENT.FORM.BEHAVIOR_HINT') }}
        </span>
      </div>

      <p
        v-if="errorKey"
        class="px-3 py-2 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11 border border-n-ruby-5"
      >
        {{ t(`INSURANCE.AGENT.ERRORS.${errorKey}`) }}
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <NextButton
          solid
          blue
          :is-loading="saving"
          :disabled="!canSubmit || saving"
          :label="t('INSURANCE.AGENT.ACTIONS.SUBMIT')"
          @click="submit"
        />
        <NextButton
          faded
          slate
          :label="t('INSURANCE.AGENT.ACTIONS.CANCEL')"
          @click="showForm = false"
        />
      </div>
    </section>
  </div>
</template>
