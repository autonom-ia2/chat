<script setup>
// "Das suas conversas" on Novo público (#2277, prototype). Three steps, like Automações: Conte (the request and
// the period), Confira (one question when the request can be read two ways, then the plan with time and cost on
// the account's own AI) and Revise (the list fills up while the conversations are read and becomes the review).
// After Conte the request stays in sight in a dark band. Leaving the screen does not cancel the search; a paid
// list is never thrown away without asking. The search lives on the server (conversationAudienceApi): coming back
// to the screen, or from the bell (`?busca=`), opens the person's search where it stands.
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AudienceSearchSteps from './AudienceSearchSteps.vue';
import AudienceSearchAsk from './AudienceSearchAsk.vue';
import AudienceSearchBand from './AudienceSearchBand.vue';
import AudienceSearchCheck from './AudienceSearchCheck.vue';
import AudienceSearchReview from './AudienceSearchReview.vue';
import AudienceSearchSaved from './AudienceSearchSaved.vue';
import AudienceConversationPeek from './AudienceConversationPeek.vue';
import { createConversationAudienceApi } from './conversationAudienceApi';
import { formatMoney } from './localeTag';

// `active`: the search is past the request (or cannot start), so the page hides the switch to the spreadsheet.
const emit = defineEmits(['use-sheet', 'active']);
const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const STEP_NUMBER = { pedido: 1, confira: 2, revise: 3, salvo: 4 };
// Who starts out of the list: the person puts them in.
const STARTS_OUT = ['fora'];
const AI_KEY_ROUTE = {
  name: 'settings_applications_integration',
  params: { integration_id: 'crm_kanban_ai' },
};

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const { isAdmin } = useAdmin();
const accountId = useMapGetter('getCurrentAccountId');
const api = createConversationAudienceApi();

const step = ref('pedido');
const hasOwnKey = ref(true);
const periods = ref({});
const request = ref('');
const period = ref('12m');
const isBusy = ref(false);
const question = ref(null);
const plan = ref(null);
const searchState = ref('lendo');
const progress = ref({ read: 0, total: 0, people: [] });
const leftOut = ref(new Set());
const seen = new Set();
const audienceName = ref('');
const saved = ref(null);
const peeking = ref(null);
const peekMessages = ref([]);
const confirmRestart = ref(null);

const hasPaidList = computed(
  () => step.value === 'revise' && progress.value.people.length > 0
);
const restartText = computed(() =>
  t(`${NS}.CONFIRM_RESTART_TEXT`, {
    brl: formatMoney(progress.value.cost?.brl, 'BRL', locale.value),
  })
);

const ask = async answer => {
  isBusy.value = true;
  try {
    const result = await api.plan({
      request: request.value,
      period: period.value,
      answer,
      anyLabel: t(`${NS}.QUESTION_ANY`),
    });
    question.value = result.question || null;
    plan.value = result.question ? null : result;
    step.value = 'confira';
  } catch (error) {
    const code = error?.response?.data?.error || error?.code;
    if (code === 'left') return;
    useAlert(
      t(
        code === 'search_in_progress'
          ? `${NS}.SEARCH_IN_PROGRESS`
          : `${NS}.PLAN_ERROR`
      )
    );
  } finally {
    isBusy.value = false;
  }
};

const onAsk = () => ask();

// "Ficaram de fora" comes in out of the list; the others come in. A person the user changed stays
// as they left it.
const onProgress = update => {
  const fresh = update.people.filter(person => !seen.has(person.id));
  fresh.forEach(person => seen.add(person.id));
  const out = fresh.filter(person => STARTS_OUT.includes(person.confidence));
  if (out.length) {
    leftOut.value = new Set([...leftOut.value, ...out.map(p => p.id)]);
  }
  progress.value = update;
  searchState.value = update.state;
};

// A search left open comes back where it stands: the question or the plan, or the list being read.
const reopen = async id => {
  const opened = await api.open(id);
  if (!opened) return;
  request.value = opened.request;
  period.value = opened.period;
  if (opened.check) {
    question.value = opened.check.question || null;
    plan.value = opened.check.question ? null : opened.check;
    step.value = 'confira';
    return;
  }
  plan.value = opened.plan;
  audienceName.value = opened.plan.name || '';
  onProgress(opened.progress);
  step.value = 'revise';
  if (
    ['fila', 'lendo'].includes(opened.progress.state) ||
    opened.progress.finishing
  ) {
    api.watch(plan.value, onProgress);
  }
};

const load = async () => {
  const result = await api.status();
  hasOwnKey.value = result.hasOwnKey;
  periods.value = result.periods;
  // Without the key the card already offers the spreadsheet; the page's switch would say it twice.
  if (!result.hasOwnKey) {
    emit('active', true);
    return;
  }
  const openId = Number(route.query.busca) || result.openSearchId;
  if (openId) await reopen(openId);
};
load().catch(() => useAlert(t(`${NS}.LOAD_ERROR`)));

const begin = async () => {
  isBusy.value = true;
  let started;
  try {
    started = await api.start();
  } catch {
    useAlert(t(`${NS}.ACTION_ERROR`));
    return;
  } finally {
    isBusy.value = false;
  }
  seen.clear();
  leftOut.value = new Set();
  progress.value = {
    read: 0,
    total: plan.value.conversations,
    people: [],
    aheadMinutes: started.aheadMinutes,
  };
  audienceName.value = plan.value.name || '';
  searchState.value = started.queued ? 'fila' : 'lendo';
  step.value = 'revise';
  api.watch(plan.value, onProgress);
};

const stop = async () => {
  try {
    await api.stop();
    searchState.value = 'parado';
  } catch {
    useAlert(t(`${NS}.ACTION_ERROR`));
  }
};
const resume = async () => {
  try {
    await api.resume(plan.value, onProgress);
    searchState.value = 'lendo';
  } catch {
    useAlert(t(`${NS}.ACTION_ERROR`));
  }
};
// Still in line: nothing was paid, so giving up needs no confirmation (the server puts the plan back).
const cancelQueued = async () => {
  try {
    await api.giveUp();
    step.value = 'confira';
  } catch {
    useAlert(t(`${NS}.ACTION_ERROR`));
  }
};

// A new request starts a new search; the one left behind stays on the server, unsaved (and stopped, if it was
// still reading: one search at a time per person).
const backToRequest = async () => {
  if (
    ['fila', 'lendo'].includes(searchState.value) &&
    step.value === 'revise'
  ) {
    try {
      await api.stop();
    } catch {
      // Still reading on the server: the screen stays on it rather than hiding a search that keeps paying.
      useAlert(t(`${NS}.ACTION_ERROR`));
      return;
    }
  }
  api.reset();
  step.value = 'pedido';
  question.value = null;
  plan.value = null;
};
const restart = () => {
  if (hasPaidList.value) {
    confirmRestart.value?.open();
    return;
  }
  backToRequest();
};
const confirmedRestart = () => {
  confirmRestart.value?.close();
  backToRequest();
};

const toggle = person => {
  const next = new Set(leftOut.value);
  if (next.has(person.id)) next.delete(person.id);
  else next.add(person.id);
  leftOut.value = next;
};
const setAll = (level, include) => {
  const ids = progress.value.people
    .filter(person => person.confidence === level)
    .map(person => person.id);
  const next = new Set(leftOut.value);
  ids.forEach(id => (include ? next.delete(id) : next.add(id)));
  leftOut.value = next;
};

const peek = async person => {
  peeking.value = person;
  peekMessages.value = [];
  try {
    peekMessages.value = await api.conversation(person.id);
  } catch {
    useAlert(t(`${NS}.LOAD_ERROR`));
  }
};
const peekIndex = computed(() =>
  progress.value.people.findIndex(p => p.id === peeking.value?.id)
);
const peekStep = offset =>
  peek(progress.value.people[peekIndex.value + offset]);
const peekUrl = computed(() =>
  peeking.value
    ? `/app/accounts/${accountId.value}/conversations/${peeking.value.conversationId}`
    : ''
);

const campaignWith = audienceId =>
  router.push({
    name: 'campaigns_journey_new',
    query: { audience: String(audienceId) },
  });

const save = async withCampaign => {
  isBusy.value = true;
  try {
    saved.value = await api.save({
      name: audienceName.value.trim(),
      ids: progress.value.people
        .filter(person => !leftOut.value.has(person.id))
        .map(person => person.id),
    });
  } catch {
    useAlert(t(`${NS}.SAVE_ERROR`));
    return;
  } finally {
    isBusy.value = false;
  }
  if (withCampaign) {
    campaignWith(saved.value.id);
    return;
  }
  step.value = 'salvo';
};

const seeAudiences = () => router.push({ name: 'campaigns_journey_audiences' });
const connectKey = () => router.push(AI_KEY_ROUTE);

watch(step, value => emit('active', value !== 'pedido'));

// The search keeps going on the server when the person leaves; only the polling stops here.
onBeforeUnmount(() => api.detach());
</script>

<template>
  <div
    class="flex flex-col gap-5 md:pb-0"
    :class="step === 'revise' ? 'pb-0' : 'pb-24'"
    data-test="audience-from-conversations"
  >
    <!-- Sem a IA da própria conta -->
    <section
      v-if="!hasOwnKey"
      class="flex flex-col items-start gap-4 rounded-3xl border border-n-weak bg-n-solid-1 p-6 shadow-sm md:p-8"
      data-test="needs-own-key"
    >
      <span
        class="grid size-12 place-items-center rounded-2xl bg-n-slate-3 text-n-slate-11"
        aria-hidden="true"
      >
        <span class="i-lucide-key-round size-6" />
      </span>
      <h2 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t(`${NS}.NO_KEY_TITLE`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ isAdmin ? t(`${NS}.NO_KEY_TEXT`) : t(`${NS}.NO_KEY_ASK_ADMIN`) }}
      </p>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
        <Button
          v-if="isAdmin"
          :label="t(`${NS}.CONNECT_KEY`)"
          icon="i-lucide-key-round"
          class="!min-h-12 !rounded-xl !px-6 !text-base"
          @click="connectKey"
        />
        <button
          type="button"
          class="inline-flex min-h-12 items-center gap-2 rounded-xl bg-n-solid-1 px-6 text-base font-medium text-n-blue-11 ring-1 ring-inset ring-n-slate-6 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="no-key-sheet"
          @click="emit('use-sheet')"
        >
          <span class="i-lucide-file-spreadsheet size-4" aria-hidden="true" />
          {{ t(`${NS}.NO_KEY_SHEET`) }}
        </button>
      </div>
    </section>

    <template v-else>
      <AudienceSearchSteps :current="STEP_NUMBER[step]" />
      <AudienceSearchAsk
        v-if="step === 'pedido'"
        v-model:request="request"
        v-model:period="period"
        :periods="periods"
        :busy="isBusy"
        @ask="onAsk"
      />
      <AudienceSearchBand
        v-if="step === 'confira' || step === 'revise'"
        :understood="step === 'revise' ? plan?.understood : ''"
        :request="request"
        :period="period"
      />
      <AudienceSearchCheck
        v-if="step === 'confira'"
        :question="question"
        :plan="plan"
        :busy="isBusy"
        @answer="ask"
        @start="begin"
        @back="backToRequest"
      />
      <AudienceSearchReview
        v-else-if="step === 'revise'"
        v-model:name="audienceName"
        :state="searchState"
        :progress="progress"
        :left-out="leftOut"
        :busy="isBusy"
        @toggle="toggle"
        @set-all="setAll"
        @peek="peek"
        @stop="stop"
        @resume="resume"
        @connect-key="connectKey"
        @cancel="cancelQueued"
        @save="save"
        @restart="restart"
      />
      <AudienceSearchSaved
        v-else-if="step === 'salvo'"
        :saved="saved"
        @create-campaign="campaignWith(saved.id)"
        @see-audience="seeAudiences"
      />
    </template>

    <AudienceConversationPeek
      :person="peeking"
      :messages="peekMessages"
      :conversation-url="peekUrl"
      :included="Boolean(peeking) && !leftOut.has(peeking.id)"
      :is-out-group="peeking?.confidence === 'fora'"
      :position="peekIndex + 1"
      :total="progress.people.length"
      @toggle="toggle(peeking)"
      @previous="peekStep(-1)"
      @next="peekStep(1)"
      @close="peeking = null"
    />
    <Dialog
      ref="confirmRestart"
      type="alert"
      :title="t(`${NS}.CONFIRM_RESTART_TITLE`)"
      :description="restartText"
      @confirm="confirmedRestart"
    >
      <template #footer>
        <div class="flex flex-col gap-3 sm:flex-row-reverse">
          <Button
            type="button"
            :label="t(`${NS}.CONFIRM_KEEP`)"
            class="!min-h-12 flex-1 !rounded-xl !text-base"
            data-test="confirm-keep"
            @click="confirmRestart?.close()"
          />
          <Button
            type="submit"
            :label="t(`${NS}.CONFIRM_RESTART_OK`)"
            variant="outline"
            color="ruby"
            class="!min-h-12 flex-1 !rounded-xl !bg-n-solid-1 !text-base"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
