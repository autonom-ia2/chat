<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingPageCard from './BookingPageCard.vue';

// A lista de páginas: carregando, erro, vazio (1 frase + 1 botão) e os cartões.
// Pausar e excluir acontecem aqui; editar, publicar (pela prévia) e ver abrem
// outra tela.
const props = defineProps({
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'edit', 'publish', 'view']);

const { t } = useI18n();
const pages = ref([]);
const loading = ref(true);
const failed = ref(false);
const busyId = ref(null);
const notices = ref({});

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await BookingPagesAPI.get();
    pages.value = data.payload || [];
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const replace = updated => {
  pages.value = pages.value.map(page =>
    page.id === updated.id ? { ...page, ...updated } : page
  );
};

const setNotice = (id, text) => {
  notices.value = { ...notices.value, [id]: text };
};

const run = async (page, action) => {
  busyId.value = page.id;
  setNotice(page.id, '');
  try {
    await action();
  } finally {
    busyId.value = null;
  }
};

const pause = page =>
  run(page, async () => {
    try {
      const { data } = await BookingPagesAPI.pause(page.id);
      replace(data.payload);
      useAlert(t('BOOKING.CARD.PAUSED_OK'));
    } catch {
      setNotice(page.id, t('BOOKING.CARD.ACTION_ERROR'));
    }
  });

const remove = page =>
  run(page, async () => {
    try {
      await BookingPagesAPI.delete(page.id);
      pages.value = pages.value.filter(item => item.id !== page.id);
      useAlert(t('BOOKING.CARD.DELETED'));
    } catch (error) {
      const blocked = error?.response?.status === 409;
      setNotice(
        page.id,
        blocked
          ? t('BOOKING.CARD.DELETE_BLOCKED')
          : t('BOOKING.CARD.ACTION_ERROR')
      );
    }
  });

onMounted(load);
</script>

<template>
  <section class="flex flex-col w-full gap-6">
    <div
      v-if="loading"
      data-loading
      aria-busy="true"
      class="flex flex-col gap-4"
    >
      <span class="sr-only">{{ t('BOOKING.LIST.LOADING') }}</span>
      <div
        v-for="item in 2"
        :key="item"
        class="h-40 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
    </div>

    <div
      v-else-if="failed"
      data-error
      role="alert"
      class="flex flex-col items-start gap-4 p-6 rounded-2xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
    >
      <p class="m-0 text-base text-n-ruby-12">{{ t('BOOKING.LIST.ERROR') }}</p>
      <button
        type="button"
        class="inline-flex items-center gap-2 min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-ruby-9 hover:bg-n-ruby-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="load"
      >
        {{ t('BOOKING.LIST.RETRY') }}
      </button>
    </div>

    <div
      v-else-if="!pages.length"
      data-empty
      class="flex flex-col items-center gap-6 px-6 py-14 text-center rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <span
        class="grid place-items-center size-16 rounded-2xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-calendar-check size-8" />
      </span>
      <p class="m-0 text-lg font-medium text-n-slate-12">
        {{
          canManage
            ? t('BOOKING.LIST.EMPTY')
            : t('BOOKING.LIST.EMPTY_VIEW_ONLY')
        }}
      </p>
      <button
        v-if="canManage"
        type="button"
        data-create
        class="inline-flex items-center gap-2 min-h-12 px-6 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('create')"
      >
        <span class="i-lucide-plus size-5" aria-hidden="true" />
        {{ t('BOOKING.LIST.CREATE') }}
      </button>
    </div>

    <template v-else>
      <div v-if="canManage" class="flex justify-end">
        <button
          type="button"
          data-create
          class="inline-flex items-center gap-2 min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('create')"
        >
          <span class="i-lucide-plus size-5" aria-hidden="true" />
          {{ t('BOOKING.LIST.NEW') }}
        </button>
      </div>
      <ul
        class="flex flex-col gap-5 p-0 m-0 list-none"
        :aria-label="t('BOOKING.LIST.LABEL')"
      >
        <li v-for="page in pages" :key="page.id">
          <BookingPageCard
            :page="page"
            :can-manage="props.canManage"
            :busy="busyId === page.id"
            :notice="notices[page.id] || ''"
            @edit="emit('edit', $event)"
            @view="emit('view', $event)"
            @publish="emit('publish', $event)"
            @pause="pause"
            @delete="remove"
          />
        </li>
      </ul>
    </template>
  </section>
</template>
