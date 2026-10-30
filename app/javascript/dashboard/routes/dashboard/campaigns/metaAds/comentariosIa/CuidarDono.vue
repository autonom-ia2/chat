<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { FOR_WHOM_LIMIT } from './useCuidado';

// Comentários que viram cliente (#2212, opção (a) do Rodrigo): o jeito escrito pelo dono, em três passos, uma ação em
// cada: o que mandar no privado → para quem, nas palavras dele → como fica, com dois comentários do post (a Prévia do
// servidor), e "Ligar". Não há palavra-gatilho: o modelo lê o "para quem" e cada comentário, e decide; quando não é o
// caso, diz "aqui não se aplica" e não manda nada (nunca lista de palavras, regra do Rodrigo de 20/09).
// No Facebook, o privado pelo Messenger espera a Meta liberar pages_messaging (F4): com `private_available` false, a
// tela diz "em breve" no lugar dos passos.
const props = defineProps({
  // O Painel do servidor: message, para_quem, phrases, private_available, unanswered.
  data: { type: Object, required: true },
  // async paraQuem => Prévia ({ recebe, nao }) ou null quando não deu para ler.
  preview: { type: Function, required: true },
  // async () => o começo da mensagem escrito pela IA a partir da legenda do post, ou '' (Rascunho). Sem ele, o passo 1
  // abre vazio.
  draft: { type: Function, default: null },
  changing: { type: Boolean, default: false },
  canSendOld: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
});

const emit = defineEmits(['done', 'leave']);

const { t } = useI18n();
const KEY = 'META_ADS_COMMENTS_AI.DONO';
// A Meta aceita até 1000 bytes (UTF-8) no texto do privado: acento e emoji ocupam mais de um byte, então a conta é em
// bytes, não em letras. O privado é só a mensagem do dono: nada é acrescentado no fim.
const LIMIT_BYTES = 1000;
const PHRASE_LIMIT = 120;
const RULES_MORE = ['SEVEN_DAYS', 'LIVE', 'REQUESTS', 'COMPLAINT'];
const SUGGESTIONS = ['PRICE', 'LINK', 'CATALOG'];

// O servidor não monta frase: o cuidado novo vem sem nenhuma, e a tela começa com a padrão, no idioma dela.
const phrases = computed(() =>
  props.data.phrases?.length
    ? props.data.phrases
    : [t('META_ADS_COMMENTS_AI.DONO.SEE.PHRASE_DEFAULT')]
);
const step = ref(1);
const message = ref(props.data.message || '');
// Como no mockup aprovado, o cuidado novo já começa no atalho mais comum; o dono troca com um toque.
const forWhom = ref(
  props.data.para_quem || t('META_ADS_COMMENTS_AI.DONO.WHO.SUGGESTIONS.PRICE')
);
const phrase = ref(phrases.value[0] || '');
const editingPhrase = ref(!phrase.value);
// A padrão muda com o idioma, que pode chegar depois de abrir a tela (endereço aberto direto): enquanto o dono não a
// trocou, a frase acompanha.
watch(phrases, (novas, antigas) => {
  if (phrase.value === antigas[0]) phrase.value = novas[0] || '';
});
const heading = ref(null);
// Passo 1 do cuidado novo, como no mockup aprovado: a mensagem já vem com um começo escrito a partir do post. Enquanto a
// IA escreve, o campo espera; o que o dono digitar nesse meio tempo não é trocado. Sem começo, o campo fica vazio, com
// o texto de sempre.
const writing = ref(false);
const suggested = ref(false);
onMounted(async () => {
  if (!props.draft || props.changing || message.value.trim()) return;
  writing.value = true;
  const texto = await props.draft();
  writing.value = false;
  if (!texto || message.value.trim()) return;
  message.value = texto;
  suggested.value = true;
});
// A Prévia do passo 3, lida de novo a cada vez que o passo abre (o "para quem" pode ter mudado).
const examples = ref(null);
const loadingExamples = ref(false);
const examplesFailed = ref(false);

const soon = computed(() => props.data.private_available === false);
const dm = computed(() => message.value.trim());
const tooLong = computed(
  () => new TextEncoder().encode(dm.value).length > LIMIT_BYTES
);
const forWhomTooLong = computed(
  () => forWhom.value.trim().length > FOR_WHOM_LIMIT
);
// Sem a Prévia (falhou), o cartão de quem recebe aparece como exemplo, com o aviso de que não deu para ler.
const recebe = computed(() => {
  if (examples.value?.recebe) return examples.value.recebe;
  return examplesFailed.value ? { sample: true } : null;
});
const nao = computed(() => examples.value?.nao || null);
const sample = computed(() => Boolean(recebe.value?.sample));
const handle = comment =>
  comment.network === 'facebook' ? comment.author : `@${comment.author}`;
const values = () => ({
  message: message.value.trim(),
  paraQuem: forWhom.value.trim(),
  phrase: phrase.value.trim() || phrases.value[0] || '',
});

// A Prévia classifica comentários com a IA: sem resposta em PREVIEW_TIMEOUT_MS, o passo 3 cai no "não deu para ler", em
// vez de girar para sempre. Voltar e abrir o passo de novo lê outra vez: só a resposta da leitura mais nova vale.
const PREVIEW_TIMEOUT_MS = 20000;
let examplesRead = 0;
const previewOrTimeout = paraQuem => {
  let timer;
  const timeout = new Promise(resolve => {
    timer = setTimeout(() => resolve(null), PREVIEW_TIMEOUT_MS);
  });
  return Promise.race([props.preview(paraQuem), timeout]).finally(() =>
    clearTimeout(timer)
  );
};
const loadExamples = async () => {
  examplesRead += 1;
  const mine = examplesRead;
  examples.value = null;
  examplesFailed.value = false;
  loadingExamples.value = true;
  const result = await previewOrTimeout(forWhom.value.trim());
  if (mine !== examplesRead) return;
  loadingExamples.value = false;
  examples.value = result;
  examplesFailed.value = !result;
};

const go = async next => {
  step.value = next;
  editingPhrase.value = !phrase.value.trim();
  if (next === 3) loadExamples();
  await nextTick();
  heading.value?.focus();
};
const canGoOn = computed(() =>
  step.value === 1
    ? Boolean(message.value.trim()) && !tooLong.value
    : Boolean(forWhom.value.trim()) && !forWhomTooLong.value
);
const canStart = computed(
  () => Boolean(phrase.value.trim() || phrases.value[0]) && !props.saving
);
const LINK =
  'min-h-11 w-fit rounded-lg border-0 bg-transparent px-2 text-start text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
const FIELD =
  '!mb-0 w-full resize-none rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';
</script>

<template>
  <section
    data-ia-dono
    :data-ia-dono-step="soon ? 'soon' : step"
    class="flex flex-col gap-5 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
  >
    <template v-if="soon">
      <span
        class="inline-flex w-fit items-center gap-1.5 rounded-full bg-n-alpha-2 px-3 py-1 text-sm font-semibold text-n-slate-11"
      >
        <span class="i-lucide-clock size-4" aria-hidden="true" />
        {{ $t(`${KEY}.SOON.BADGE`) }}
      </span>
      <h3
        ref="heading"
        tabindex="-1"
        class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
      >
        {{ $t(`${KEY}.SOON.TITLE`) }}
      </h3>
      <p class="m-0 text-base leading-6 text-n-slate-11">
        {{ $t(`${KEY}.SOON.TEXT`) }}
      </p>
    </template>

    <template v-else>
      <div class="flex flex-col gap-2">
        <div
          class="flex gap-1.5"
          role="progressbar"
          :aria-valuenow="step"
          aria-valuemin="1"
          aria-valuemax="3"
          :aria-label="$t(`${KEY}.STEP`, { step, total: 3 })"
        >
          <span
            v-for="bar in 3"
            :key="bar"
            class="h-1.5 flex-1 rounded-full"
            :class="bar <= step ? 'bg-n-brand' : 'bg-n-alpha-2'"
          />
        </div>
        <p class="m-0 text-sm font-medium text-n-slate-11">
          {{ $t(`${KEY}.STEP`, { step, total: 3 }) }}
        </p>
      </div>

      <template v-if="step === 1">
        <div class="flex flex-col gap-1">
          <h3
            ref="heading"
            tabindex="-1"
            class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
          >
            {{ $t(`${KEY}.WHAT.TITLE`) }}
          </h3>
          <p
            data-ia-dono-what-text
            class="m-0 text-base leading-6 text-n-slate-11"
          >
            {{ $t(`${KEY}.WHAT.${suggested ? 'SUGGESTED' : 'TEXT'}`) }}
          </p>
        </div>
        <p
          v-if="writing"
          data-ia-dono-writing
          role="status"
          class="m-0 flex items-center gap-2 text-sm font-medium text-n-slate-11"
        >
          <span
            class="i-lucide-sparkles size-4 animate-pulse text-n-violet-11"
            aria-hidden="true"
          />
          {{ $t(`${KEY}.WHAT.WRITING`) }}
        </p>
        <textarea
          id="ia-dono-message"
          v-model="message"
          data-ia-dono-message
          :aria-label="$t(`${KEY}.WHAT.TITLE`)"
          :aria-invalid="tooLong"
          :aria-busy="writing"
          :placeholder="writing ? '' : $t(`${KEY}.WHAT.PLACEHOLDER`)"
          :class="[FIELD, { 'animate-pulse bg-n-alpha-1': writing }]"
          class="min-h-[8.5rem]"
        />
        <p
          v-if="tooLong"
          role="alert"
          data-ia-dono-too-long
          class="m-0 text-sm font-medium text-n-ruby-11"
        >
          {{ $t(`${KEY}.WHAT.TOO_LONG`) }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.WHAT.ALL_IN_ONE`) }}
        </p>
      </template>

      <template v-else-if="step === 2">
        <div class="flex flex-col gap-1">
          <h3
            ref="heading"
            tabindex="-1"
            class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
          >
            {{ $t(`${KEY}.WHO.TITLE`) }}
          </h3>
          <p class="m-0 text-base leading-6 text-n-slate-11">
            {{ $t(`${KEY}.WHO.TEXT`) }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="suggestion in SUGGESTIONS"
            :key="suggestion"
            type="button"
            data-ia-dono-suggestion
            :aria-pressed="
              forWhom === $t(`${KEY}.WHO.SUGGESTIONS.${suggestion}`)
            "
            class="min-h-11 rounded-full border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              forWhom === $t(`${KEY}.WHO.SUGGESTIONS.${suggestion}`)
                ? 'bg-n-blue-3 text-n-blue-11 ring-1 ring-inset ring-n-blue-8'
                : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1'
            "
            @click="forWhom = $t(`${KEY}.WHO.SUGGESTIONS.${suggestion}`)"
          >
            {{ $t(`${KEY}.WHO.SUGGESTIONS.${suggestion}`) }}
          </button>
        </div>
        <label
          for="ia-dono-who"
          class="flex flex-col gap-2 text-sm font-medium text-n-slate-11"
        >
          {{ $t(`${KEY}.WHO.OWN`) }}
          <textarea
            id="ia-dono-who"
            v-model="forWhom"
            data-ia-dono-who
            rows="2"
            :aria-invalid="forWhomTooLong"
            :placeholder="$t(`${KEY}.WHO.PLACEHOLDER`)"
            :class="FIELD"
            class="min-h-[4.5rem] font-normal"
          />
        </label>
        <p
          v-if="forWhomTooLong"
          role="alert"
          data-ia-dono-who-too-long
          class="m-0 text-sm font-medium text-n-ruby-11"
        >
          {{ $t(`${KEY}.WHO.TOO_LONG`, { max: FOR_WHOM_LIMIT }) }}
        </p>
      </template>

      <template v-else>
        <div class="flex flex-col gap-2">
          <h3
            ref="heading"
            tabindex="-1"
            class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
          >
            {{ $t(`${KEY}.SEE.TITLE`) }}
          </h3>
          <p
            class="m-0 flex flex-wrap items-center gap-2 text-base leading-6 text-n-slate-11"
          >
            {{ $t(`${KEY}.SEE.YOU_ASKED`) }}
            <span
              data-ia-dono-who-chip
              class="rounded-full bg-n-blue-3 px-3 py-1 text-sm font-medium text-n-blue-11"
            >
              {{ forWhom.trim() }}
            </span>
          </p>
        </div>

        <div
          v-if="loadingExamples"
          data-ia-dono-examples-loading
          role="status"
          aria-busy="true"
          class="flex flex-col gap-3"
        >
          <p
            class="m-0 flex items-center gap-2 text-sm font-medium text-n-slate-11"
          >
            <span
              class="i-lucide-sparkles size-4 animate-pulse text-n-violet-11"
              aria-hidden="true"
            />
            {{ $t(`${KEY}.SEE.LOADING`) }}
          </p>
          <div class="h-24 animate-pulse rounded-xl bg-n-alpha-2" />
        </div>

        <ol v-else class="m-0 flex list-none flex-col gap-3 p-0">
          <li
            v-if="recebe"
            data-ia-dono-example="recebe"
            class="flex flex-col gap-3 rounded-xl p-4 ring-1 ring-inset ring-n-weak"
          >
            <p
              v-if="examplesFailed"
              role="alert"
              data-ia-dono-examples-failed
              class="m-0 text-sm font-medium text-n-amber-11"
            >
              {{ $t(`${KEY}.SEE.PREVIEW_ERROR`) }}
            </p>
            <p class="m-0 text-base leading-6 text-n-slate-12">
              <span
                v-if="!examplesFailed"
                class="block text-sm font-semibold text-n-slate-11"
              >
                {{ sample ? $t(`${KEY}.SEE.SAMPLE`) : handle(recebe) }}
              </span>
              {{ sample ? $t(`${KEY}.SEE.SAMPLE_TEXT`) : recebe.text }}
            </p>
            <span
              class="inline-flex w-fit items-center gap-1.5 rounded-full bg-n-teal-3 px-3 py-1 text-sm font-semibold text-n-teal-11"
            >
              <span class="i-lucide-send size-4" aria-hidden="true" />
              {{ $t(`${KEY}.SEE.${sample ? 'GETS' : 'GETS_BEFORE'}`) }}
            </span>
            <div class="flex flex-col gap-1.5">
              <p class="m-0 text-sm font-semibold text-n-slate-11">
                {{ $t(`${KEY}.SEE.IN_DM`) }}
              </p>
              <p
                data-ia-dono-bubble
                class="m-0 max-w-xl self-end whitespace-pre-line rounded-2xl rounded-br-md bg-n-blue-9 px-4 py-3 text-sm leading-6 text-white"
              >
                {{ dm }}
              </p>
            </div>
            <div class="flex flex-col gap-1.5">
              <p class="m-0 text-sm font-semibold text-n-slate-11">
                {{ $t(`${KEY}.SEE.IN_COMMENT`) }}
              </p>
              <div
                v-if="!editingPhrase"
                class="flex flex-wrap items-center gap-2"
              >
                <p
                  data-ia-dono-phrase
                  class="m-0 rounded-2xl rounded-tl-md bg-n-alpha-2 px-4 py-2 text-sm leading-6 text-n-slate-12"
                >
                  {{ phrase }}
                </p>
                <button
                  type="button"
                  data-ia-dono-phrase-edit
                  :class="LINK"
                  @click="editingPhrase = true"
                >
                  {{ $t(`${KEY}.SEE.PHRASE_EDIT`) }}
                </button>
              </div>
              <div v-else class="flex flex-col gap-2">
                <input
                  v-model="phrase"
                  type="text"
                  data-ia-dono-phrase-field
                  :maxlength="PHRASE_LIMIT"
                  :aria-label="$t(`${KEY}.SEE.IN_COMMENT`)"
                  :class="FIELD"
                  class="min-h-11"
                  @keydown.enter.prevent="editingPhrase = !phrase.trim()"
                />
                <Button
                  variant="faded"
                  color="slate"
                  :label="$t(`${KEY}.SEE.PHRASE_DONE`)"
                  :disabled="!phrase.trim()"
                  class="!min-h-11 w-fit !rounded-xl"
                  @click="editingPhrase = false"
                />
              </div>
            </div>
          </li>
          <li
            v-if="nao"
            data-ia-dono-example="nao"
            class="flex flex-col gap-3 rounded-xl p-4 ring-1 ring-inset ring-n-weak"
          >
            <p class="m-0 text-base leading-6 text-n-slate-12">
              <span class="block text-sm font-semibold text-n-slate-11">
                {{ handle(nao) }}
              </span>
              {{ nao.text }}
            </p>
            <span
              class="inline-flex w-fit items-center gap-1.5 rounded-full bg-n-alpha-2 px-3 py-1 text-sm font-semibold text-n-slate-11"
            >
              <span class="i-lucide-minus size-4" aria-hidden="true" />
              {{ $t(`${KEY}.SEE.SKIPS`) }}
            </span>
            <p class="m-0 text-sm leading-6 text-n-slate-11">
              {{ $t(`${KEY}.SEE.SKIPS_WHY`) }}
            </p>
          </li>
        </ol>

        <!-- No celular, o aviso dos que já estão aqui fica no conteúdo, para o pé preso ficar baixo. -->
        <p
          v-if="canSendOld && !changing"
          class="m-0 text-sm leading-6 text-n-slate-12 sm:hidden"
        >
          {{
            $t(`${KEY}.OLD_NOTE`, { count: data.unanswered }, data.unanswered)
          }}
        </p>
        <div data-ia-dono-rules class="flex flex-col gap-1">
          <p
            class="m-0 flex items-start gap-2 text-sm leading-6 text-n-slate-12"
          >
            <span
              class="i-lucide-info mt-1 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{ $t(`${KEY}.RULES.ONCE`) }}
          </p>
          <details class="group">
            <summary
              class="flex min-h-11 w-fit cursor-pointer list-none items-center gap-1 rounded-lg px-2 text-sm font-medium text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            >
              <span
                class="i-lucide-chevron-right size-4 transition-transform group-open:rotate-90"
                aria-hidden="true"
              />
              {{ $t(`${KEY}.RULES.MORE`) }}
            </summary>
            <ul
              class="m-0 mt-1 flex list-none flex-col gap-2 rounded-xl bg-n-alpha-1 p-4"
            >
              <li
                v-for="rule in RULES_MORE"
                :key="rule"
                class="text-sm leading-6 text-n-slate-12"
              >
                {{ $t(`${KEY}.RULES.${rule}`) }}
              </li>
            </ul>
          </details>
        </div>
      </template>

      <!-- A ação do passo fica presa ao pé: no passo 3 ela não some depois da prévia. No celular, o botão redondo do
           menu do painel ocupa o canto de baixo: o botão principal fica acima dele, e o link, ao lado. -->
      <div
        data-ia-dono-bar
        class="sticky bottom-0 z-10 -mx-5 -mb-5 flex flex-row flex-wrap items-center gap-2 rounded-b-2xl border-0 border-t border-solid border-n-weak bg-n-solid-1 px-5 pb-[4.5rem] pt-3 sm:-mx-6 sm:-mb-6 sm:flex-row sm:flex-wrap sm:items-center sm:gap-x-4 sm:px-6 sm:pb-4"
      >
        <!-- Antes de ligar, junto do botão: o que acontece com as perguntas que já estão no post (a pergunta vem depois). -->
        <p
          v-if="step === 3 && canSendOld && !changing"
          data-ia-dono-old-note
          class="m-0 mb-2 hidden w-full text-sm leading-6 text-n-slate-12 sm:block"
        >
          {{
            $t(`${KEY}.OLD_NOTE`, { count: data.unanswered }, data.unanswered)
          }}
        </p>
        <Button
          v-if="step < 3"
          data-ia-dono-next
          icon="i-lucide-arrow-right"
          :label="$t(`${KEY}.NEXT`)"
          :disabled="!canGoOn"
          class="!min-h-12 flex-1 !rounded-xl sm:flex-none"
          @click="go(step + 1)"
        />
        <Button
          v-else
          data-ia-dono-start
          :icon="changing ? 'i-lucide-check' : 'i-lucide-sparkles'"
          :label="
            changing
              ? $t('META_ADS_COMMENTS_AI.ON.SAVE_CHANGES')
              : $t(`${KEY}.START`)
          "
          :disabled="!canStart"
          :is-loading="saving"
          class="!min-h-12 flex-1 !rounded-xl sm:flex-none"
          @click="emit('done', values())"
        />
        <button
          v-if="step > 1"
          type="button"
          data-ia-dono-previous
          class="order-first sm:order-none"
          :class="LINK"
          @click="go(step - 1)"
        >
          {{ $t(`${KEY}.PREVIOUS`) }}
        </button>
        <button
          v-else-if="changing"
          type="button"
          data-ia-dono-leave
          class="ms-16 sm:ms-0"
          :class="LINK"
          @click="emit('leave')"
        >
          {{ $t('META_ADS_COMMENTS_AI.ON.LEAVE_CHANGES') }}
        </button>
      </div>
    </template>
  </section>
</template>
