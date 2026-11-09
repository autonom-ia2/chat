<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { withWords } from '../dinheiroDoAnuncio';
import { soltarMidia } from '../midiaDoAnuncio';
import { duplicarAnuncio, trocarCriativo } from '../criacaoNaMeta';
import { mudarStatus } from '../gestaoDoAnuncio';
import MetaAdsAdStatus from './MetaAdsAdStatus.vue';
import MetaAdsMediaPicker from './MetaAdsMediaPicker.vue';

// Anúncios da Meta (#2198, #2778): cuidar de um anúncio que já existe, além de pausar e do orçamento.
// - Duplicar: cópia da campanha inteira, pausada, com orçamento próprio igual ao do original. A confirmação diz o
//   valor por extenso; depois, o "Ativar anúncio" da cópia fica ali mesmo.
// - Trocar foto ou texto (ligado para todos em #2804): a Meta não muda o criativo; o servidor cria outro e põe no
//   anúncio. A Meta analisa de novo, e a confirmação diz isso antes. Se a Meta recusar trocar neste anúncio
//   (`swap_refused`), o mesmo diálogo oferece a cópia pausada já com a foto e o texto novos, e a confirmação lembra de
//   pausar este quando ativar a cópia. Com a cópia no ar, o botão "Pausar o original" fica ali mesmo.
// - Cópia não confirmada (a Meta não respondeu e ela não apareceu na busca): a pessoa confere no Gerenciador de
//   Anúncios e cria de novo pela tela, com a mesma chave (#2804).
// - Carrossel e post impulsionado (`creativeKind` vazio) não têm uma foto para trocar: só o "Duplicar".
// Só aparece em anúncio criado pelo Chat2You (opção a do Rodrigo, 09/11); a gestão diz isso (`created_here`).
const props = defineProps({
  adId: { type: String, required: true },
  adName: { type: String, default: '' },
  image: { type: String, default: '' },
  text: { type: String, default: '' },
  budget: { type: Object, default: null },
  // 'image' ou 'video': o que dá para trocar (foto por foto, vídeo por vídeo). Vazio: só duplicar.
  creativeKind: { type: String, default: '' },
  // A situação escolhida do original ('ACTIVE' | 'PAUSED' …): o "Pausar o original" só aparece com ele ativo.
  originalStatus: { type: String, default: '' },
  // O anúncio no Gerenciador de Anúncios da Meta, para conferir a cópia não confirmada.
  managerUrl: { type: String, default: '' },
});

const emit = defineEmits(['reviewing', 'originalPaused']);

const { t, locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.CARE';
const saving = ref(false);

const duplicateDialog = ref(null);
const copy = ref(null);
const copyGestao = ref(null);
// A miniatura da cópia que já nasceu com a foto nova; `fromSwap`: a cópia veio de "Trocar a foto" (o ativar dela lembra
// de pausar o original).
const copyImage = ref('');
const fromSwap = ref(false);

const duplicateHint = computed(() => {
  const budget = props.budget;
  if (!budget) return t(`${KEY}.DUPLICATE_HINT_NO_BUDGET`);
  const value = withWords(budget.amount, budget.currency, locale.value);
  return budget.kind === 'lifetime'
    ? t(`${KEY}.DUPLICATE_HINT_TOTAL`, { value })
    : t(`${KEY}.DUPLICATE_HINT`, { value });
});

// A foto atual do anúncio, como o seletor de mídia mostra.
const current = computed(() => {
  if (!props.image) return null;
  return props.creativeKind === 'video'
    ? {
        kind: 'video',
        url: props.image,
        poster: props.image,
        source: 'current',
      }
    : { kind: 'image', url: props.image, source: 'current' };
});

const showCopy = (created, gestao, { image = '', swap = false } = {}) => {
  copy.value = created;
  copyGestao.value = gestao;
  copyImage.value = image;
  fromSwap.value = swap;
};

const copyHint = computed(() => {
  const budget = props.budget;
  if (!budget) return t(`${KEY}.SWAP_AS_COPY_HINT_NO_BUDGET`);
  const value = withWords(budget.amount, budget.currency, locale.value);
  return budget.kind === 'lifetime'
    ? t(`${KEY}.SWAP_AS_COPY_HINT_TOTAL`, { value })
    : t(`${KEY}.SWAP_AS_COPY_HINT`, { value });
});

// Só diz "nada foi gasto" quando o servidor garante (`nothing_created: true`). Sem resposta, em andamento (409), falha do
// servidor ou `nothing_created: false`: a Meta pode ter feito, então pede para conferir.
// Recusa do nosso servidor antes de mudar algo (sem permissão, anúncio não achado, pedido recusado).
const REFUSED_STATUSES = [403, 404, 422];
const surelyNothing = error =>
  REFUSED_STATUSES.includes(error?.response?.status) &&
  error.response.data?.nothing_created !== false;

// O original já terminou: não há o que copiar.
const copyError = error => {
  if (error?.response?.data?.error === 'invalid_dates')
    return t(`${KEY}.ENDED`);
  return t(surelyNothing(error) ? `${KEY}.DUPLICATE_ERROR` : `${KEY}.UNSURE`);
};

// A cópia que ficou não confirmada: o pedido como foi (`creative` e se veio de "Trocar"), para o recriar mandar igual.
const unconfirmed = ref(null);

// Duplicar, a cópia com a foto nova e o recriar passam por aqui. Não confirmada: no lugar do aviso que some, o cartão
// diz para conferir no Gerenciador e oferece criar de novo.
const runCopy = async (creative, { swap = false, recriar = false } = {}) => {
  try {
    const created = await duplicarAnuncio(props.adId, creative, { recriar });
    // Só o texto mudou: a cópia não tem foto nova para mostrar.
    const newPhoto = creative && creative.media !== current.value;
    showCopy(
      created,
      { status: 'PAUSED', effective_status: 'PAUSED', can_change: true },
      {
        image: newPhoto ? creative.media.poster || creative.media.url : '',
        swap,
      }
    );
    unconfirmed.value = null;
    return true;
  } catch (error) {
    if (error?.response?.data?.error === 'unconfirmed') {
      unconfirmed.value = { creative, swap };
      return true;
    }
    useAlert(copyError(error));
    return false;
  }
};

const duplicate = async () => {
  saving.value = true;
  if (await runCopy(null)) duplicateDialog.value?.close();
  saving.value = false;
};

const recreate = async () => {
  saving.value = true;
  await runCopy(unconfirmed.value.creative, {
    swap: unconfirmed.value.swap,
    recriar: true,
  });
  saving.value = false;
};

const copyChanged = status => {
  copyGestao.value = { ...copyGestao.value, status, effective_status: status };
};

// A cópia com a foto nova está no ar e o original também: o botão para pausar o original, com confirmação.
const pauseDialog = ref(null);
const showPauseOriginal = computed(
  () =>
    fromSwap.value &&
    copyGestao.value?.status === 'ACTIVE' &&
    props.originalStatus === 'ACTIVE'
);
const pauseOriginal = async () => {
  saving.value = true;
  try {
    await mudarStatus(props.adId, 'PAUSED');
    emit('originalPaused');
    pauseDialog.value?.close();
    useAlert(t(`${KEY}.PAUSE_ORIGINAL_DONE`));
  } catch {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS.ERROR'));
  } finally {
    saving.value = false;
  }
};

// Trocar: a mídia e o texto atuais já vêm na tela; "Continuar" só liga quando algo mudou, e pede a confirmação. A foto
// atual chega só com o endereço (`source: 'current'`): sem as medidas, o seletor não diz o formato dela, e ela não vai
// no pedido (o servidor mantém a do anúncio).
const changeDialog = ref(null);
const media = ref(null);
// Enquanto a foto nova sobe para a Meta, o "Continuar" espera.
const uploading = ref(false);
const newText = ref('');
const confirming = ref(false);
// A Meta recusou trocar neste anúncio: o diálogo vira a confirmação da cópia com a foto nova.
const asCopy = ref(false);
// Texto vazio não vale: o anúncio precisa de texto.
const changed = computed(
  () =>
    Boolean(media.value) &&
    newText.value.trim() !== '' &&
    (media.value !== current.value || newText.value.trim() !== props.text)
);

const changeTitle = computed(() => {
  if (asCopy.value) return t(`${KEY}.SWAP_AS_COPY_CONFIRM_TITLE`);
  return t(
    confirming.value ? `${KEY}.CHANGE_CONFIRM_TITLE` : `${KEY}.CHANGE_TITLE`
  );
});
const saveLabel = computed(() => {
  if (!confirming.value) return t(`${KEY}.CONTINUE`);
  return t(asCopy.value ? `${KEY}.DUPLICATE_CONFIRM` : `${KEY}.CHANGE_CONFIRM`);
});

const openChange = () => {
  media.value = current.value;
  newText.value = props.text;
  confirming.value = false;
  asCopy.value = false;
  changeDialog.value?.open();
};
const closeChange = () => {
  if (media.value !== current.value) soltarMidia(media.value);
  changeDialog.value?.close();
};

const saveChange = async () => {
  if (!confirming.value) {
    confirming.value = true;
    return;
  }
  saving.value = true;
  const creative = { media: media.value, text: newText.value.trim() };
  if (asCopy.value) {
    if (await runCopy(creative, { swap: true })) changeDialog.value?.close();
    saving.value = false;
    return;
  }
  try {
    const result = await trocarCriativo(props.adId, creative);
    emit('reviewing', {
      effective_status: result.effective_status,
      image: creative.media.poster || creative.media.url,
      text: creative.text,
    });
    useAlert(t(`${KEY}.CHANGE_DONE`));
    changeDialog.value?.close();
  } catch (error) {
    if (error?.response?.data?.error === 'swap_refused') asCopy.value = true;
    else {
      useAlert(
        t(surelyNothing(error) ? `${KEY}.CHANGE_ERROR` : `${KEY}.CHANGE_UNSURE`)
      );
    }
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <section
    data-ad-care
    class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
  >
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ $t(`${KEY}.TITLE`) }}
    </h3>
    <Button
      v-if="!creativeKind"
      data-ad-care-duplicate
      :variant="copy ? 'faded' : null"
      :color="copy ? 'slate' : null"
      icon="i-lucide-copy"
      :label="$t(`${KEY}.DUPLICATE`)"
      class="w-full sm:w-auto sm:self-start"
      @click="duplicateDialog?.open()"
    />
    <div v-else class="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
      <Button
        data-ad-care-duplicate
        variant="faded"
        color="slate"
        icon="i-lucide-copy"
        :label="$t(`${KEY}.DUPLICATE`)"
        class="w-full sm:w-auto"
        @click="duplicateDialog?.open()"
      />
      <Button
        data-ad-care-change
        variant="faded"
        color="slate"
        icon="i-lucide-image"
        :label="$t(`${KEY}.CHANGE`)"
        class="w-full sm:w-auto"
        @click="openChange"
      />
    </div>
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t(creativeKind ? `${KEY}.HINT` : `${KEY}.HINT_DUPLICATE`) }}
    </p>

    <!-- Cópia não confirmada: conferir no Gerenciador e, se ela não estiver lá, criar de novo. -->
    <div
      v-if="unconfirmed"
      data-ad-care-unconfirmed
      role="status"
      class="flex flex-col items-start gap-3 rounded-xl bg-n-amber-2 p-4"
    >
      <p class="m-0 flex gap-2 text-sm text-n-amber-12">
        <span
          class="i-lucide-circle-help mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.COPY_UNCONFIRMED`) }}
      </p>
      <a
        v-if="managerUrl"
        :href="managerUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex min-h-11 items-center gap-1.5 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        {{ $t(`${KEY}.OPEN_MANAGER`) }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
      </a>
      <Button
        data-ad-care-recreate
        outline
        :label="$t(`${KEY}.RECREATE`)"
        :is-loading="saving"
        :disabled="saving"
        class="w-full sm:w-auto"
        @click="recreate"
      />
    </div>

    <!-- A cópia recém-criada: pausada, com o "Ativar anúncio" dela à mão. -->
    <div
      v-if="copy"
      data-ad-care-copy
      class="flex flex-col items-start gap-2 rounded-xl bg-n-alpha-1 p-4"
    >
      <div class="flex items-center gap-3">
        <img
          v-if="copyImage"
          :src="copyImage"
          alt=""
          data-ad-care-copy-image
          class="size-14 shrink-0 rounded-lg object-cover"
        />
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{
            copyImage
              ? $t(`${KEY}.SWAP_AS_COPY_DONE`, { name: copy.name })
              : $t(`${KEY}.DUPLICATE_DONE`, { name: copy.name })
          }}
        </p>
      </div>
      <p class="m-0 text-xs text-n-slate-11">
        {{ $t(`${KEY}.DUPLICATE_DONE_HINT`) }}
      </p>
      <MetaAdsAdStatus
        :ad-id="copy.ad_id"
        :ad-name="copy.name"
        :gestao="copyGestao"
        :budget="copy.budget"
        :activate-note="fromSwap ? $t(`${KEY}.SWAP_AS_COPY_ACTIVATE`) : ''"
        tone="light"
        can-manage
        @changed="copyChanged"
      />
      <!-- A cópia com a foto nova no ar: pausar o original para não gastar em dobro, ali mesmo. -->
      <div
        v-if="showPauseOriginal"
        data-ad-care-pause-original
        class="flex w-full flex-col items-start gap-2 border-t border-n-weak pt-3"
      >
        <p class="m-0 text-sm text-n-slate-12">
          {{ $t(`${KEY}.PAUSE_ORIGINAL_HINT`) }}
        </p>
        <Button
          icon="i-lucide-pause"
          :label="$t(`${KEY}.PAUSE_ORIGINAL`)"
          class="w-full sm:w-auto"
          @click="pauseDialog?.open()"
        />
      </div>
    </div>

    <Dialog
      ref="duplicateDialog"
      type="alert"
      :title="$t(`${KEY}.DUPLICATE_TITLE`, { name: adName })"
      :description="duplicateHint"
      :is-loading="saving"
      @confirm="duplicate"
    >
      <template #footer>
        <div
          class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:items-center"
        >
          <Button
            variant="faded"
            color="slate"
            :label="$t(`${KEY}.CANCEL`)"
            class="w-full sm:flex-1"
            type="button"
            @click="duplicateDialog?.close()"
          />
          <Button
            data-ad-care-duplicate-confirm
            :label="$t(`${KEY}.DUPLICATE_CONFIRM`)"
            class="w-full sm:flex-1"
            :is-loading="saving"
            :disabled="saving"
            type="submit"
          />
        </div>
      </template>
    </Dialog>

    <Dialog
      ref="changeDialog"
      :title="changeTitle"
      width="lg"
      overflow-y-auto
      :is-loading="saving"
      @confirm="saveChange"
    >
      <p
        v-if="confirming"
        data-ad-care-change-review
        class="m-0 flex gap-2 rounded-xl bg-n-amber-2 p-3 text-sm text-n-amber-12"
      >
        <span
          class="i-lucide-clock mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{
          asCopy
            ? `${$t(`${KEY}.SWAP_REFUSED`)} ${copyHint}`
            : $t(`${KEY}.CHANGE_REVIEW`)
        }}
      </p>
      <div v-else class="flex min-w-0 flex-col gap-4">
        <MetaAdsMediaPicker
          v-model="media"
          replacing
          :only="creativeKind"
          @uploading="uploading = $event"
        />
        <TextArea
          v-model="newText"
          data-ad-care-text
          :label="$t(`${KEY}.TEXT`)"
          :max-length="500"
          show-character-count
          min-height="6rem"
        />
      </div>
      <template #footer>
        <div
          class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:items-center"
        >
          <Button
            variant="faded"
            color="slate"
            :label="$t(`${KEY}.CANCEL`)"
            class="w-full sm:flex-1"
            type="button"
            @click="closeChange"
          />
          <Button
            data-ad-care-change-save
            :label="saveLabel"
            class="w-full sm:flex-1"
            :is-loading="saving"
            :disabled="saving || uploading || !changed"
            type="submit"
          />
        </div>
      </template>
    </Dialog>
    <!-- Pausar o original (#2804): a mesma confirmação do topo do anúncio. -->
    <Dialog
      ref="pauseDialog"
      type="alert"
      :title="
        $t('CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS.PAUSE_TITLE', {
          name: adName,
        })
      "
      :description="$t('CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS.PAUSE_HINT')"
      :confirm-button-label="$t(`${KEY}.PAUSE_ORIGINAL`)"
      :cancel-button-label="$t(`${KEY}.CANCEL`)"
      :is-loading="saving"
      @confirm="pauseOriginal"
    />
  </section>
</template>
