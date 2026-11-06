<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { novaChave, publicarPost } from '../criacaoNaMeta';
import {
  REDES,
  alvoDoImpulsionar,
  erroDoPublicar,
  faltaNoPost,
  juntarPublicado,
  lugarDoPost,
  motivosDasRedes,
  publicacaoIncerta,
  redesQueDao,
} from '../criarPost';
import MetaAdsCreatePublish from './MetaAdsCreatePublish.vue';
import MetaAdsCreatePublishReview from './MetaAdsCreatePublishReview.vue';
import MetaAdsCreatePublished from './MetaAdsCreatePublished.vue';

// Anúncios da Meta (#2198 PR 3, #2653), criar post: escrever → conferir → publicado. Publica na hora (não tem pausa),
// depois de uma confirmação que diz onde. "Publicar e impulsionar" publica e segue para o impulsionar com o post já
// escolhido (`boost`), que nasce pausado como no PR 2.
//
// A chave da tentativa nasce na primeira confirmação e vale enquanto o post não muda: tocar de novo, ou o "Tentar de
// novo" numa rede, nunca publica duas vezes. Mudou alguma coisa, chave nova, menos depois de uma resposta incerta
// (sem resposta, ou o servidor não sabe se a Meta publicou): aí a chave só muda quando a pessoa diz que conferiu na
// rede e não saiu ("Conferi, publicar de novo").
const props = defineProps({
  pages: { type: Array, default: () => [] },
  // As permissões do token: { facebook, instagram }.
  publish: { type: Object, default: () => ({}) },
});

// back: volta à escolha do que fazer. boost: { page_id, post_source, post_id }. done: volta ao painel. signIn: entrar
// de novo com o Facebook (sem a permissão de publicar).
const emit = defineEmits(['back', 'boost', 'done', 'signIn']);

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';

const STEPS = ['EDIT', 'REVIEW', 'DONE'];
const step = ref('EDIT');
const heading = ref(null);
const review = ref(null);
const saving = ref(false);
const error = ref('');
const published = ref(null);
// A última tentativa pode ter publicado: a chave fica até a pessoa conferir.
const uncertain = ref(false);
let chave = null;

const pageOf = id => props.pages.find(page => page.id === id);
const firstPage = props.pages.length === 1 ? props.pages[0].id : null;
const post = ref({
  page_id: firstPage,
  networks: redesQueDao(
    motivosDasRedes(props.publish, pageOf(firstPage)?.instagram)
  ),
  media: null,
  caption: '',
  uploading: false,
});

const page = computed(() => pageOf(post.value.page_id));
const instagram = computed(() => page.value?.instagram || null);
const reasons = computed(() => motivosDasRedes(props.publish, instagram.value));
// Só as redes marcadas que dão (trocar de Página pode apagar o Instagram).
const networks = computed(() =>
  post.value.networks.filter(rede => !reasons.value[rede])
);
const missing = computed(() => faltaNoPost(post.value, reasons.value));
const noNetworkAtAll = computed(
  () => !redesQueDao(reasons.value).length && Boolean(post.value.page_id)
);

// Trocou a Página: as redes que dão nela já vêm marcadas.
watch(
  () => post.value.page_id,
  () => {
    post.value = { ...post.value, networks: redesQueDao(reasons.value) };
  }
);
// O post mudou depois de uma confirmação: a próxima é outra tentativa.
watch(
  () => [
    post.value.page_id,
    networks.value,
    post.value.media,
    post.value.caption,
  ],
  () => {
    if (!uncertain.value) chave = null;
  },
  { deep: true }
);

const focusHeading = () => nextTick(() => heading.value?.focus());
watch(step, () => {
  error.value = '';
  focusHeading();
});

const publishedNetworks = computed(() =>
  REDES.filter(rede => published.value?.[rede])
);
const title = computed(() => {
  if (step.value === 'EDIT') return t(`${KEY}.PUBLISH.TITLE`);
  if (step.value === 'REVIEW') return t(`${KEY}.PUBLISH_REVIEW.TITLE`);
  return t(`${KEY}.PUBLISHED.TITLE.${lugarDoPost(publishedNetworks.value)}`);
});
const hint = computed(() => {
  if (step.value === 'DONE') return t(`${KEY}.PUBLISHED.HINT`);
  return t(
    `${KEY}.${step.value === 'EDIT' ? 'PUBLISH' : 'PUBLISH_REVIEW'}.HINT`
  );
});

const back = () => {
  if (step.value === 'REVIEW') step.value = 'EDIT';
  else emit('back');
};

const showError = failure => {
  const code = erroDoPublicar(failure);
  // Outra tentativa ainda publicando não tira a dúvida da anterior.
  uncertain.value =
    publicacaoIncerta(code) || (uncertain.value && code === 'IN_PROGRESS');
  error.value = t(`${KEY}.PUBLISH_REVIEW.ERRORS.${code}`);
};
// "Conferi e não saiu em nenhuma rede": a próxima confirmação é outra tentativa.
const checkedNotPublished = () => {
  uncertain.value = false;
  chave = null;
  error.value = '';
};

// `fresh`: a pessoa conferiu que não saiu naquela rede; só ela vai com chave nova.
const send = async (redes, fresh = null) => {
  chave = chave || novaChave();
  return publicarPost({
    chave: fresh || chave,
    pageId: post.value.page_id,
    networks: redes,
    caption: post.value.caption,
    mediaId: post.value.media.signed_id,
  });
};

const publishNow = async boost => {
  if (saving.value) return;
  saving.value = true;
  error.value = '';
  try {
    const result = await send(networks.value);
    published.value = result;
    const target = alvoDoImpulsionar(result);
    if (boost && target && !result.failed.length) {
      emit('boost', { page_id: post.value.page_id, ...target });
    } else {
      step.value = 'DONE';
    }
  } catch (failure) {
    showError(failure);
  } finally {
    saving.value = false;
    review.value?.close();
  }
};

const retry = async (rede, checked = false) => {
  saving.value = true;
  error.value = '';
  try {
    const result = await send([rede], checked ? novaChave() : null);
    published.value = juntarPublicado(published.value, result);
  } catch (failure) {
    // Vídeo ainda em preparo, ou resposta incerta: a frase da rede diz o que fazer.
    const code = erroDoPublicar(failure);
    if (code === 'IN_PROGRESS') {
      error.value = t(`${KEY}.PUBLISH_REVIEW.ERRORS.IN_PROGRESS`);
      return;
    }
    let motivo = 'meta_refused';
    if (code === 'PROCESSING') motivo = 'processing';
    else if (publicacaoIncerta(code)) motivo = 'unconfirmed';
    published.value = {
      ...published.value,
      errors: { ...published.value.errors, [rede]: motivo },
    };
    if (motivo === 'meta_refused') {
      error.value = t(`${KEY}.PUBLISHED.RETRY_FAILED.${rede.toUpperCase()}`);
    }
  } finally {
    saving.value = false;
  }
};

const boostPublished = () =>
  emit('boost', {
    page_id: post.value.page_id,
    ...alvoDoImpulsionar(published.value),
  });

const submit = () => {
  if (missing.value) return;
  if (step.value === 'EDIT') step.value = 'REVIEW';
};
</script>

<template>
  <div
    data-create-publish-flow
    :data-create-publish-step="step"
    class="contents"
  >
    <button
      v-if="step !== 'DONE'"
      type="button"
      data-create-publish-back
      class="inline-flex min-h-11 items-center gap-1.5 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="back"
    >
      <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
      {{ $t(`${KEY}.BACK`) }}
    </button>

    <form
      class="flex min-w-0 flex-col gap-6 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-8"
      @submit.prevent="submit"
    >
      <div class="flex flex-col gap-2">
        <span
          v-if="step !== 'DONE'"
          data-create-progress
          class="text-xs font-medium text-n-slate-10"
        >
          {{
            $t(`${KEY}.PROGRESS`, { step: STEPS.indexOf(step) + 1, total: 2 })
          }}
        </span>
        <h2
          ref="heading"
          tabindex="-1"
          class="m-0 text-xl font-semibold text-n-slate-12 focus:outline-none"
        >
          {{ title }}
        </h2>
        <p class="m-0 max-w-prose text-sm leading-6 text-n-slate-11">
          {{ hint }}
        </p>
      </div>

      <MetaAdsCreatePublish
        v-if="step === 'EDIT'"
        v-model="post"
        :pages="pages"
        :page-name="page?.name"
        :instagram="instagram"
        :reasons="reasons"
        @uploading="post = { ...post, uploading: $event }"
      />
      <MetaAdsCreatePublishReview
        v-else-if="step === 'REVIEW'"
        ref="review"
        :post="{ ...post, networks }"
        :page-name="page?.name"
        :instagram="instagram"
        :saving="saving"
        @publish="publishNow"
      />
      <MetaAdsCreatePublished
        v-else
        :published="published"
        :retrying="saving"
        @retry="retry"
        @boost="boostPublished"
        @done="emit('done')"
      />

      <div
        v-if="noNetworkAtAll && step === 'EDIT'"
        data-create-publish-no-permission
        class="flex flex-col items-start gap-2"
      >
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.PUBLISH.NO_NETWORK`) }}
        </p>
        <Button
          variant="faded"
          :label="$t(`${KEY}.PUBLISH.SIGN_IN`)"
          @click="emit('signIn')"
        />
      </div>

      <p
        v-if="error"
        data-create-publish-error
        role="alert"
        class="m-0 flex gap-2 rounded-xl bg-n-ruby-2 p-3 text-sm text-n-ruby-12"
      >
        <span
          class="i-lucide-circle-alert mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ error }}
      </p>
      <button
        v-if="error && uncertain && step === 'REVIEW'"
        type="button"
        data-create-publish-checked
        class="inline-flex min-h-11 items-center self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="checkedNotPublished"
      >
        {{ $t(`${KEY}.PUBLISH_REVIEW.CHECKED_NOT_PUBLISHED`) }}
      </button>

      <div
        v-if="step !== 'DONE'"
        data-create-actions
        class="fixed inset-x-0 bottom-0 z-30 flex gap-3 border-t border-n-weak bg-n-solid-1 pb-[calc(1rem+env(safe-area-inset-bottom))] pl-20 pr-4 pt-3 md:static md:z-auto md:border-0 md:bg-transparent md:p-0"
      >
        <div
          class="flex min-w-0 flex-1 flex-col gap-2 md:flex-row md:items-center md:gap-4"
        >
          <template v-if="step === 'EDIT'">
            <Button
              class="w-full md:w-auto"
              type="submit"
              data-create-next="PUBLISH"
              :label="$t(`${KEY}.NEXT`)"
              :disabled="Boolean(missing)"
            />
            <p
              v-if="missing"
              data-create-block-reason
              role="status"
              class="order-first m-0 text-xs text-n-slate-11 md:order-none md:text-sm"
            >
              {{ $t(`${KEY}.PUBLISH.${missing}`) }}
            </p>
          </template>
          <template v-else>
            <Button
              class="w-full md:w-auto"
              type="button"
              data-create-publish-now
              :label="$t(`${KEY}.PUBLISH_REVIEW.PUBLISH`)"
              :is-loading="saving"
              @click="review?.open(false)"
            />
            <Button
              class="w-full md:w-auto"
              type="button"
              variant="faded"
              data-create-publish-and-boost
              :label="$t(`${KEY}.PUBLISH_REVIEW.PUBLISH_AND_BOOST`)"
              :disabled="saving"
              @click="review?.open(true)"
            />
          </template>
        </div>
      </div>
    </form>
  </div>
</template>
