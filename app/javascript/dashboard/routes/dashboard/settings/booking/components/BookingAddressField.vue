<script setup>
import { computed, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { addressProblem, addressUrl, cleanAddress } from '../bookingAddress';

// Endereço da página (#1282): o link curto `…/a/<nome>`. Já vem sugerido a
// partir do nome do atendimento; a pessoa só confere ou troca. Mostra o link
// como vai ficar e diz, em texto, se o endereço está livre. Enquanto a pessoa
// não mexe no campo, o endereço acompanha o nome do atendimento.
const props = defineProps({
  title: { type: String, default: '' },
  pageId: { type: Number, default: null },
  // O endereço que a página já tem salvo ('' = nenhum).
  savedName: { type: String, default: '' },
  error: { type: String, default: '' },
});

const model = defineModel({ type: String, default: '' });
const { t } = useI18n();
const id = useId();

const WAIT_MS = 500;
// 'idle' | 'checking' | 'free' | 'own' | 'problem'
const status = ref('idle');
const problem = ref(null);
const followsTitle = ref(!props.savedName && !model.value);
let timer = null;
let request = 0;

const later = action => {
  clearTimeout(timer);
  timer = setTimeout(action, WAIT_MS);
};

const showProblem = code => {
  problem.value = code;
  status.value = 'problem';
};

// Só a resposta do pedido mais novo vale: a de um nome já trocado é ignorada.
const check = async name => {
  request += 1;
  const current = request;
  status.value = 'checking';
  try {
    const { data } = await BookingPagesAPI.shortName({
      name,
      pageId: props.pageId,
    });
    if (current !== request) return;
    if (data.payload.available) status.value = 'free';
    else showProblem(data.payload.problem);
  } catch {
    // Sem resposta, não afirma nada: o servidor confere de novo ao salvar.
    if (current === request) status.value = 'idle';
  }
};

const review = name => {
  clearTimeout(timer);
  request += 1;
  problem.value = null;
  if (!name) {
    status.value = 'idle';
    return;
  }
  const local = addressProblem(name);
  if (local) {
    showProblem(local);
    return;
  }
  if (name === props.savedName) {
    status.value = 'own';
    return;
  }
  status.value = 'checking';
  later(() => check(name));
};

const suggest = async () => {
  if (!followsTitle.value || !props.title.trim()) return;
  try {
    const { data } = await BookingPagesAPI.shortName({
      title: props.title,
      pageId: props.pageId,
    });
    if (followsTitle.value && data.payload.suggestion) {
      model.value = data.payload.suggestion;
    }
  } catch {
    // Sem sugestão o campo fica vazio e a pessoa escreve o endereço.
  }
};

const onInput = event => {
  followsTitle.value = false;
  const cleaned = cleanAddress(event.target.value);
  // O campo mostra sempre o valor limpo, mesmo quando ele não mudou.
  event.target.value = cleaned;
  model.value = cleaned;
};

watch(model, review);
watch(
  () => props.title,
  () => {
    if (followsTitle.value) later(suggest);
  }
);

onMounted(() => {
  review(model.value);
  suggest();
});
onBeforeUnmount(() => clearTimeout(timer));

const statusText = computed(() => {
  if (status.value === 'checking') return t('BOOKING.ADDRESS.CHECKING');
  if (status.value === 'free') return t('BOOKING.ADDRESS.FREE');
  if (status.value === 'own') return t('BOOKING.ADDRESS.OWN');
  return '';
});
const problemText = computed(() => {
  if (status.value === 'problem' && problem.value) {
    return t(`BOOKING.ADDRESS.PROBLEMS.${problem.value.toUpperCase()}`);
  }
  return props.error;
});
const isChanging = computed(
  () => !!props.savedName && model.value !== props.savedName
);
</script>

<template>
  <div data-address class="flex flex-col gap-2">
    <label :for="id" class="text-base font-semibold text-n-slate-12">
      {{ t('BOOKING.ADDRESS.LABEL') }}
    </label>
    <p :id="`${id}-hint`" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.ADDRESS.HINT') }}
    </p>
    <input
      :id="id"
      data-address-input
      type="text"
      inputmode="url"
      autocapitalize="none"
      autocomplete="off"
      spellcheck="false"
      :value="model"
      :aria-invalid="problemText ? 'true' : undefined"
      :aria-describedby="`${id}-hint ${id}-status`"
      class="block w-full reset-base !mb-0 min-h-12 px-4 text-base rounded-xl border-0 bg-n-solid-1 text-n-slate-12 ring-1 ring-inset placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
      :class="problemText ? 'ring-n-ruby-8' : 'ring-n-weak'"
      @input="onInput"
    />
    <p
      data-address-preview
      class="m-0 text-base font-medium break-all text-n-slate-12"
    >
      {{
        model
          ? t('BOOKING.ADDRESS.PREVIEW', { url: addressUrl(model) })
          : t('BOOKING.ADDRESS.EMPTY')
      }}
    </p>
    <div :id="`${id}-status`" role="status" aria-live="polite">
      <p
        v-if="problemText"
        data-address-problem
        class="m-0 text-base text-n-ruby-11"
      >
        {{ problemText }}
      </p>
      <p
        v-else-if="statusText"
        data-address-status
        class="m-0 text-base"
        :class="status === 'free' ? 'text-n-teal-11' : 'text-n-slate-11'"
      >
        {{ statusText }}
      </p>
    </div>
    <p
      v-if="isChanging"
      data-address-warning
      class="m-0 text-base text-n-amber-11"
    >
      {{ t('BOOKING.ADDRESS.CHANGE_WARNING') }}
    </p>
  </div>
</template>
