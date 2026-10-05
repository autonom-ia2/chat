<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MetaAdsConnectDialog from './MetaAdsConnectDialog.vue';

// "Meta campaign names" block of the Links and QR codes page
// (docs/crm/origens-nomes-meta.md §2 and §5). Account administrators only: the
// page renders it for them alone (the API answers 403 to anyone else).
const { t, locale } = useI18n();

const connection = ref(null);
const isLoading = ref(false);
const loadFailed = ref(false);
const isRemoving = ref(false);
const connectDialog = ref(null);
const removeDialog = ref(null);

const state = computed(() => {
  if (!connection.value?.configured) return 'not_connected';
  return connection.value.status === 'active' ? 'connected' : 'attention';
});

const STATE_VIEW = {
  not_connected: {
    icon: 'i-lucide-plug',
    badge: 'bg-n-alpha-2 text-n-slate-11',
  },
  connected: {
    icon: 'i-lucide-circle-check',
    badge: 'bg-n-teal-3 text-n-teal-11',
  },
  attention: {
    icon: 'i-lucide-triangle-alert',
    badge: 'bg-n-amber-3 text-n-amber-11',
  },
};
const view = computed(() => STATE_VIEW[state.value]);
const statusLabel = computed(
  () =>
    ({
      not_connected: t(
        'CRM_KANBAN.TRACKED_LINKS.META_ADS.STATUS.NOT_CONNECTED'
      ),
      connected: t('CRM_KANBAN.TRACKED_LINKS.META_ADS.STATUS.CONNECTED'),
      attention: t('CRM_KANBAN.TRACKED_LINKS.META_ADS.STATUS.ATTENTION'),
    })[state.value]
);

// "há 2 horas" from the timestamp itself, never from translated text.
const RELATIVE_UNITS = [
  { unit: 'year', seconds: 365 * 24 * 60 * 60 },
  { unit: 'month', seconds: 30 * 24 * 60 * 60 },
  { unit: 'day', seconds: 24 * 60 * 60 },
  { unit: 'hour', seconds: 60 * 60 },
  { unit: 'minute', seconds: 60 },
  { unit: 'second', seconds: 1 },
];
const intlLocale = computed(() => (locale.value || 'en').replace('_', '-'));
const checkedAgo = computed(() => {
  const date = new Date(connection.value?.last_checked_at || '');
  if (!connection.value?.last_checked_at || Number.isNaN(date.getTime())) {
    return null;
  }
  const seconds = (date.getTime() - Date.now()) / 1000;
  const { unit, seconds: size } =
    RELATIVE_UNITS.find(item => Math.abs(seconds) >= item.seconds) ||
    RELATIVE_UNITS.at(-1);
  return {
    label: t('CRM_KANBAN.TRACKED_LINKS.META_ADS.CHECKED', {
      time: new Intl.RelativeTimeFormat(intlLocale.value, {
        numeric: 'auto',
      }).format(Math.round(seconds / size), unit),
    }),
    title: new Intl.DateTimeFormat(intlLocale.value, {
      dateStyle: 'long',
      timeStyle: 'short',
    }).format(date),
  };
});

const fetchConnection = async () => {
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.get();
    connection.value = data;
  } catch {
    loadFailed.value = true;
  } finally {
    isLoading.value = false;
  }
};

const onConnected = data => {
  connection.value = data;
  useAlert(t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.SAVED'));
};

const removeConnection = async () => {
  isRemoving.value = true;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.remove();
    connection.value = data || { configured: false };
    removeDialog.value.close();
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE_SUCCESS'));
  } catch {
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE_ERROR'));
  } finally {
    isRemoving.value = false;
  }
};

const connectLabel = computed(() => {
  if (state.value === 'connected')
    return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REPLACE');
  if (state.value === 'attention')
    return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.RECONNECT');
  return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.CONNECT');
});

onMounted(fetchConnection);
</script>

<template>
  <section
    aria-labelledby="meta-ads-names-title"
    class="rounded-xl border border-n-weak bg-n-solid-1 p-5"
    data-testid="meta-ads-names"
  >
    <div class="flex flex-wrap items-start gap-4">
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-tags size-5" />
      </span>
      <div class="min-w-0 flex-1 basis-60">
        <div class="flex flex-wrap items-center gap-2">
          <h3 id="meta-ads-names-title" class="m-0 text-sm font-semibold">
            {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.TITLE') }}
          </h3>
          <span
            v-if="!isLoading && !loadFailed"
            class="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium"
            :class="view.badge"
            data-testid="meta-ads-status"
          >
            <span :class="view.icon" class="size-3" aria-hidden="true" />
            {{ statusLabel }}
          </span>
        </div>
        <p class="m-0 mt-1 text-sm leading-relaxed text-n-slate-11">
          {{
            state === 'connected'
              ? t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DESCRIPTION_CONNECTED')
              : t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DESCRIPTION')
          }}
        </p>

        <p
          v-if="isLoading"
          role="status"
          class="m-0 mt-3 flex items-center gap-2 text-sm text-n-slate-11"
        >
          <span class="i-lucide-loader-circle size-4 animate-spin" />
          {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.LOADING') }}
        </p>
        <p
          v-else-if="loadFailed"
          role="alert"
          class="m-0 mt-3 text-sm text-n-ruby-11"
        >
          {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.LOAD_ERROR') }}
        </p>
        <p
          v-else-if="state === 'connected' && checkedAgo"
          class="m-0 mt-3 text-xs text-n-slate-11"
          :title="checkedAgo.title"
        >
          {{ checkedAgo.label }}
        </p>
        <div
          v-else-if="state === 'attention'"
          class="mt-3 rounded-lg bg-n-amber-2 px-3 py-2.5 text-sm leading-5 text-n-amber-12"
          data-testid="meta-ads-attention"
        >
          <p class="m-0">
            {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.ATTENTION_HINT') }}
          </p>
          <p
            v-if="connection.last_error"
            class="m-0 mt-1 break-words text-xs text-n-amber-11"
          >
            {{
              t('CRM_KANBAN.TRACKED_LINKS.META_ADS.LAST_ERROR', {
                error: connection.last_error,
              })
            }}
          </p>
        </div>
      </div>
    </div>

    <div class="mt-4 flex flex-wrap justify-end gap-2">
      <Button
        v-if="loadFailed"
        :label="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.RETRY')"
        slate
        outline
        class="h-11"
        @click="fetchConnection"
      />
      <template v-else-if="!isLoading">
        <Button
          v-if="state !== 'not_connected'"
          :label="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE')"
          icon="i-lucide-trash-2"
          ruby
          ghost
          class="h-11"
          data-testid="meta-ads-remove"
          @click="removeDialog.open()"
        />
        <Button
          :label="connectLabel"
          :icon="state === 'not_connected' ? 'i-lucide-plug' : ''"
          :color="state === 'connected' ? 'slate' : 'blue'"
          :variant="state === 'connected' ? 'outline' : 'solid'"
          class="h-11"
          data-testid="meta-ads-connect"
          @click="connectDialog.open()"
        />
      </template>
    </div>

    <MetaAdsConnectDialog ref="connectDialog" @connected="onConnected" />
    <Dialog
      ref="removeDialog"
      type="alert"
      :title="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE_TITLE')"
      :description="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE_HINT')"
      :confirm-button-label="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.REMOVE')"
      :is-loading="isRemoving"
      @confirm="removeConnection"
    />
  </section>
</template>
