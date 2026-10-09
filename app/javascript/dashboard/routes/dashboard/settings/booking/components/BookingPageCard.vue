<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingLinkActions from './BookingLinkActions.vue';

// Um cartão por página: nome, situação (No ar, Pausada ou Rascunho), aviso de
// atenção, o link (só no ar) e, para quem pode mudar, Editar, Pausar/Publicar e
// Excluir (com confirmação).
const props = defineProps({
  page: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  // Recado da última ação nesta página (ex.: o que falta para publicar).
  notice: { type: String, default: '' },
});

const emit = defineEmits(['edit', 'view', 'publish', 'pause', 'delete']);

const { t } = useI18n();
const confirming = ref(false);

const published = computed(() => props.page.enabled === true);
// Rascunho: desligada e ainda falta algo para publicar (o `missing` do index).
const status = computed(() => {
  if (published.value) return 'LIVE';
  return props.page.missing?.length ? 'DRAFT' : 'PAUSED';
});
const statusLabel = computed(() => {
  if (status.value === 'LIVE') return t('BOOKING.CARD.STATUS.LIVE');
  if (status.value === 'DRAFT') return t('BOOKING.CARD.STATUS.DRAFT');
  return t('BOOKING.CARD.STATUS.PAUSED');
});
const STATUS_TONE = {
  LIVE: { badge: 'bg-n-teal-3 text-n-teal-11', dot: 'bg-n-teal-9' },
  PAUSED: { badge: 'bg-n-slate-3 text-n-slate-11', dot: 'bg-n-slate-9' },
  DRAFT: { badge: 'bg-n-amber-3 text-n-amber-11', dot: 'bg-n-amber-9' },
};
const title = computed(() => props.page.title || t('BOOKING.CARD.UNTITLED'));

const SECONDARY =
  'inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';

const confirmBox = ref(null);
const askDelete = async () => {
  confirming.value = true;
  await nextTick();
  confirmBox.value?.focus();
};

const confirmDelete = () => {
  confirming.value = false;
  emit('delete', props.page);
};
</script>

<template>
  <article
    :data-page="page.id"
    class="flex flex-col gap-5 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 shadow-sm"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col gap-1 min-w-0">
        <h3 class="m-0 text-lg font-semibold text-n-slate-12 break-words">
          {{ title }}
        </h3>
        <p class="m-0 text-base text-n-slate-11">
          {{ t('BOOKING.CARD.UPCOMING', page.upcoming_meetings_count || 0) }}
        </p>
      </div>
      <span
        data-status
        class="inline-flex items-center gap-2 px-3 py-1 text-sm font-semibold rounded-full"
        :data-status-key="status"
        :class="STATUS_TONE[status].badge"
      >
        <span
          class="size-2 rounded-full"
          :class="STATUS_TONE[status].dot"
          aria-hidden="true"
        />
        {{ statusLabel }}
      </span>
    </header>

    <p
      v-if="page.attention"
      data-attention
      role="status"
      class="flex items-start gap-3 m-0 px-4 py-3 text-base rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      <span
        class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0"
        aria-hidden="true"
      />
      {{ t('BOOKING.CARD.ATTENTION') }}
    </p>

    <BookingLinkActions
      v-if="published && page.public_url"
      :url="page.public_url"
    />

    <p
      v-if="notice"
      data-notice
      role="alert"
      class="m-0 px-4 py-3 text-base rounded-xl bg-n-ruby-3 text-n-ruby-12"
    >
      {{ notice }}
    </p>

    <footer
      class="flex flex-wrap items-center gap-2 pt-4 border-t border-n-weak"
    >
      <template v-if="canManage">
        <button
          type="button"
          data-edit
          :disabled="busy"
          :class="SECONDARY"
          class="text-white bg-n-blue-9 ring-n-blue-9 hover:bg-n-blue-10"
          @click="emit('edit', page)"
        >
          <span class="i-lucide-pencil size-4" aria-hidden="true" />
          {{ t('BOOKING.CARD.EDIT') }}
        </button>
        <button
          v-if="published"
          type="button"
          data-pause
          :disabled="busy"
          :class="SECONDARY"
          class="text-n-slate-12 bg-n-solid-1 ring-n-weak hover:ring-n-blue-7"
          @click="emit('pause', page)"
        >
          <span class="i-lucide-pause size-4" aria-hidden="true" />
          {{ t('BOOKING.CARD.PAUSE') }}
        </button>
        <button
          v-else
          type="button"
          data-publish
          :disabled="busy"
          :class="SECONDARY"
          class="text-n-slate-12 bg-n-solid-1 ring-n-weak hover:ring-n-blue-7"
          @click="emit('publish', page)"
        >
          <span class="i-lucide-play size-4" aria-hidden="true" />
          {{ t('BOOKING.CARD.PUBLISH') }}
        </button>
        <button
          v-if="!confirming"
          type="button"
          data-delete
          :disabled="busy"
          :class="SECONDARY"
          class="ms-auto text-n-ruby-11 bg-n-solid-1 ring-n-weak hover:ring-n-ruby-7"
          @click="askDelete"
        >
          <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
          {{ t('BOOKING.CARD.DELETE') }}
        </button>
      </template>
      <button
        v-else
        type="button"
        data-view
        :class="SECONDARY"
        class="text-n-slate-12 bg-n-solid-1 ring-n-weak hover:ring-n-blue-7"
        @click="emit('view', page)"
      >
        <span class="i-lucide-eye size-4" aria-hidden="true" />
        {{ t('BOOKING.CARD.VIEW') }}
      </button>
    </footer>

    <div
      v-if="canManage && confirming"
      ref="confirmBox"
      data-confirm
      role="alertdialog"
      tabindex="-1"
      :aria-label="t('BOOKING.CARD.CONFIRM_DELETE')"
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    >
      <p class="m-0 text-base font-medium text-n-ruby-12">
        {{ t('BOOKING.CARD.CONFIRM_DELETE') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-confirm-yes
          :class="SECONDARY"
          class="text-white bg-n-ruby-9 ring-n-ruby-9 hover:bg-n-ruby-10"
          @click="confirmDelete"
        >
          {{ t('BOOKING.CARD.CONFIRM_YES') }}
        </button>
        <button
          type="button"
          data-confirm-no
          :class="SECONDARY"
          class="text-n-slate-12 bg-n-solid-1 ring-n-weak"
          @click="confirming = false"
        >
          {{ t('BOOKING.CARD.CONFIRM_NO') }}
        </button>
      </div>
    </div>
  </article>
</template>
