<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { errorMessageKey, relativeTime } from '../metaAdsHelpers';

// Anúncios da Meta (#1047): a conexão pronta, em uma faixa. Mostra com o que está ligado e quando
// foi verificado; "Precisa de atenção" quando a Meta recusou o acesso salvo.
const props = defineProps({
  connection: { type: Object, required: true },
});

const emit = defineEmits(['removed', 'reconnect']);

const { t, locale } = useI18n();
const removeDialog = ref(null);
const removing = ref(false);

const attention = computed(() => props.connection.status !== 'active');
const partnerName = computed(
  () => props.connection.partner?.business_name || 'Hub2You'
);
const modeLabel = computed(() =>
  props.connection.mode === 'partner'
    ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.MODE_PARTNER', {
        partner: partnerName.value,
      })
    : t('CRM_KANBAN.META_ADS_HUB.SUMMARY.MODE_TOKEN')
);
const verified = computed(() => {
  const time = relativeTime(
    props.connection.verified_at || props.connection.last_checked_at,
    locale.value
  );
  return time ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.VERIFIED', { time }) : null;
});

const remove = async () => {
  removing.value = true;
  try {
    await CrmMetaAdsConnectionAPI.remove();
    useAlert(t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVED'));
    removeDialog.value?.close();
    emit('removed');
  } catch (error) {
    useAlert(t(errorMessageKey(error)));
  } finally {
    removing.value = false;
  }
};
</script>

<template>
  <section
    data-meta-ads-summary
    class="flex flex-col gap-4 p-4 border shadow-sm rounded-2xl bg-n-solid-1 sm:p-6"
    :class="attention ? 'border-n-amber-7' : 'border-n-teal-7'"
  >
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="flex items-start gap-3 min-w-0">
        <span
          class="grid flex-none rounded-2xl size-12 place-items-center"
          :class="
            attention
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-teal-3 text-n-teal-11'
          "
          aria-hidden="true"
        >
          <span
            :class="
              attention ? 'i-lucide-triangle-alert' : 'i-lucide-circle-check'
            "
            class="size-5"
          />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <h3 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{
              attention
                ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.ATTENTION')
                : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONNECTED_TO', {
                    account: connection.ad_account?.name || '',
                  })
            }}
          </h3>
          <p v-if="attention" class="m-0 text-sm text-n-amber-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.ATTENTION_HINT') }}
          </p>
          <p class="flex flex-wrap m-0 text-sm text-n-slate-11 gap-x-3 gap-y-1">
            <span>{{ modeLabel }}</span>
            <span>
              {{
                connection.pixel
                  ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.PIXEL', {
                      pixel: connection.pixel.name || connection.pixel.id,
                    })
                  : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.NO_PIXEL')
              }}
            </span>
            <span data-summary-sales>
              {{
                connection.sales_signal?.enabled
                  ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SALES_ON')
                  : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SALES_OFF')
              }}
            </span>
            <span v-if="verified">{{ verified }}</span>
          </p>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="attention"
          class="!min-h-11 !rounded-xl"
          data-summary-reconnect
          icon="i-lucide-plug"
          :label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.RECONNECT')"
          @click="emit('reconnect')"
        />
        <Button
          class="!min-h-11 !rounded-xl"
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-unplug"
          :label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE')"
          @click="removeDialog?.open()"
        />
      </div>
    </div>
    <p v-if="!attention" class="m-0 text-sm text-n-slate-11">
      {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.NEXT') }}
    </p>

    <Dialog
      ref="removeDialog"
      type="alert"
      :title="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE_TITLE')"
      :description="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE_HINT')"
      :confirm-button-label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE')"
      :is-loading="removing"
      @confirm="remove"
    />
  </section>
</template>
