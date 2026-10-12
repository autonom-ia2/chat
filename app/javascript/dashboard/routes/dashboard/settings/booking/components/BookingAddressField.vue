<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  useId,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import { addressProblem, addressUrl, cleanAddress } from '../bookingAddress';

// Endereço da página (#1282, #1299): o link curto `…/a/<conta>/<página>`.
// A parte da conta é fixa; a da página já vem sugerida a partir do nome do
// atendimento. Por padrão o passo mostra só o link pronto e o botão "Mudar
// endereço": o campo de texto abre quando a pessoa pede ou quando o endereço
// não serve (o servidor recusou, a conferência achou problema, ou não veio
// sugestão). Enquanto a pessoa não mexe no campo de uma página sem endereço
// salvo, o endereço acompanha o nome do atendimento.
const props = defineProps({
  title: { type: String, default: '' },
  pageId: { type: Number, default: null },
  // O `<conta>` do link: vem do servidor e não muda aqui. Vazio só na conta
  // que ainda não tem endereço: ele nasce quando a página é salva.
  accountAddress: { type: String, default: '' },
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
// O campo de texto à vista. Depois de aberto, fica como a pessoa deixar.
const open = ref(false);
// O último endereço que o servidor sugeriu: já veio conferido como livre.
const suggested = ref('');
// O endereço que estava no campo quando o erro de fora chegou.
const refusedName = ref(null);
const input = ref(null);
let checkTimer = null;
let suggestTimer = null;
let checkRequest = 0;
let suggestRequest = 0;

const showProblem = code => {
  problem.value = code;
  status.value = 'problem';
};

// Só a resposta do pedido mais novo vale: a de um nome já trocado é ignorada.
const check = async name => {
  checkRequest += 1;
  const current = checkRequest;
  try {
    const { data } = await BookingPagesAPI.shortName({
      name,
      pageId: props.pageId,
    });
    if (current !== checkRequest) return;
    if (data.payload.available) status.value = 'free';
    else showProblem(data.payload.problem);
  } catch {
    // Sem resposta, não afirma nada: o servidor confere de novo ao salvar.
    if (current === checkRequest) status.value = 'idle';
  }
};

const localStatus = name => {
  if (!name) return 'idle';
  if (name === props.savedName) return 'own';
  return name === suggested.value ? 'free' : null;
};

const review = name => {
  clearTimeout(checkTimer);
  checkRequest += 1;
  problem.value = null;
  const formatProblem = addressProblem(name);
  if (formatProblem) {
    showProblem(formatProblem);
    return;
  }
  status.value = localStatus(name) || 'checking';
  if (status.value !== 'checking') return;
  checkTimer = setTimeout(() => check(name), WAIT_MS);
};

const suggest = async () => {
  if (!followsTitle.value) return;
  suggestRequest += 1;
  const current = suggestRequest;
  try {
    const { data } = await BookingPagesAPI.shortName({
      title: props.title,
      pageId: props.pageId,
    });
    if (current !== suggestRequest || !followsTitle.value) return;
    suggested.value = data.payload.suggestion || '';
    if (suggested.value) model.value = suggested.value;
    else open.value = true;
  } catch {
    // Sem sugestão, o campo abre para a pessoa escrever o endereço.
    if (current === suggestRequest && followsTitle.value && !model.value) {
      open.value = true;
    }
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
    if (!followsTitle.value) return;
    clearTimeout(suggestTimer);
    suggestTimer = setTimeout(suggest, WAIT_MS);
  }
);
// O erro de fora vale para o endereço que estava no campo quando ele chegou.
watch(
  () => props.error,
  value => {
    if (value) refusedName.value = model.value;
  },
  { immediate: true }
);

onMounted(() => {
  review(model.value);
  suggest();
});
onBeforeUnmount(() => {
  clearTimeout(checkTimer);
  clearTimeout(suggestTimer);
});

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
  return model.value === refusedName.value ? props.error : '';
});
// Endereço com problema abre o campo, e ele não fecha sozinho depois.
watch(
  problemText,
  value => {
    if (value) open.value = true;
  },
  { immediate: true }
);

const isChanging = computed(
  () => !!props.savedName && model.value !== props.savedName
);
// O que o leitor de tela lê junto do campo: só o que está na tela.
const describedBy = computed(() =>
  [props.accountAddress ? 'prefix' : null, 'hint', 'status']
    .filter(Boolean)
    .map(part => `${id}-${part}`)
    .join(' ')
);
// A parte fixa antes do campo, sem o site: o link inteiro está na linha de cima.
const prefix = computed(() => `…/a/${props.accountAddress}/`);
const previewText = computed(() => {
  if (model.value) {
    return t('BOOKING.ADDRESS.PREVIEW', {
      url: addressUrl(model.value, props.accountAddress || '…'),
    });
  }
  // Recolhido e ainda sem endereço: a sugestão está a caminho.
  return open.value
    ? t('BOOKING.ADDRESS.EMPTY')
    : t('BOOKING.ADDRESS.CHECKING');
});

// Com problema à vista o campo não recolhe: o aviso não pode sumir.
const toggle = async () => {
  if (open.value && problemText.value) return;
  open.value = !open.value;
  if (!open.value) return;
  await nextTick();
  input.value?.focus();
};
</script>

<template>
  <div data-address class="flex flex-col gap-2">
    <p :id="`${id}-label`" class="m-0 text-base font-semibold text-n-slate-12">
      {{ t('BOOKING.ADDRESS.LABEL') }}
    </p>
    <p
      data-address-preview
      class="m-0 text-base font-medium break-all text-n-slate-12"
    >
      {{ previewText }}
    </p>
    <button
      type="button"
      data-address-change
      :aria-expanded="open ? 'true' : 'false'"
      :aria-controls="open ? `${id}-panel` : undefined"
      class="inline-flex items-center self-start gap-2 px-3 -mx-3 text-base font-medium min-h-11 rounded-xl text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="toggle"
    >
      <span class="i-lucide-pencil size-4 shrink-0" aria-hidden="true" />
      {{ t('BOOKING.ADDRESS.CHANGE') }}
    </button>
    <div
      v-if="open"
      :id="`${id}-panel`"
      data-address-panel
      class="flex flex-col gap-2"
    >
      <p :id="`${id}-hint`" class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.ADDRESS.HINT') }}
      </p>
      <div
        class="flex items-center rounded-xl bg-n-solid-1 ring-1 ring-inset focus-within:ring-2 focus-within:ring-n-brand"
        :class="problemText ? 'ring-n-ruby-8' : 'ring-n-weak'"
      >
        <span
          v-if="accountAddress"
          :id="`${id}-prefix`"
          data-address-prefix
          class="shrink-0 max-w-[55%] truncate ps-4 text-base text-n-slate-10"
        >
          {{ prefix }}
        </span>
        <input
          ref="input"
          data-address-input
          type="text"
          inputmode="url"
          autocapitalize="none"
          autocomplete="off"
          spellcheck="false"
          :value="model"
          :aria-labelledby="`${id}-label`"
          :aria-invalid="problemText ? 'true' : undefined"
          :aria-describedby="describedBy"
          :class="accountAddress ? 'ps-0' : 'ps-4'"
          class="flex-1 min-w-0 reset-base !mb-0 min-h-12 pe-4 text-base border-0 bg-transparent text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-0"
          @input="onInput"
        />
      </div>
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
