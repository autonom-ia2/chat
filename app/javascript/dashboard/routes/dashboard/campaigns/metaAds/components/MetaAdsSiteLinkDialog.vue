<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import {
  originHost,
  parseAllowedOrigins,
} from 'dashboard/components-next/Campaigns/TrackedLinks/trackedLinkWebsite';

// Anúncios da Meta › Destino (#2338): ligar a página do site ali mesmo, sem ir a Links e QR codes. A pessoa só cola
// o endereço da página; o nome sai do próprio endereço e o WhatsApp é o da conta (com mais de um, ela escolhe). Por
// baixo é o mesmo link de site de Links e QR codes (usage 'website'), então a página aparece lá também. O campo é texto,
// não `url`: o navegador recusaria o endereço sem "https://", que é como a pessoa costuma colar.
const emit = defineEmits(['created']);

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.DESTINATIONS.LINK_DIALOG';
const dialog = ref(null);
const address = ref('');
const touched = ref(false);
const saving = ref(false);
const failed = ref(false);

const inboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const inboxOptions = computed(() =>
  (inboxes.value || []).map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const inboxId = ref(null);
const chosenInbox = computed(
  () =>
    inboxId.value ??
    (inboxOptions.value.length === 1 ? inboxOptions.value[0].value : null)
);

const origins = computed(() => parseAllowedOrigins(address.value));
const showError = computed(
  () => touched.value && address.value.trim() && !origins.value.isValid
);
const canSave = computed(
  () => origins.value.isValid && chosenInbox.value && !saving.value
);

const open = () => {
  address.value = '';
  touched.value = false;
  failed.value = false;
  inboxId.value = null;
  dialog.value?.open();
};

const save = async () => {
  touched.value = true;
  if (!canSave.value) return;
  saving.value = true;
  failed.value = false;
  try {
    const [origin] = origins.value.origins;
    const { data } = await CrmMetaAdsConnectionAPI.createSitePage({
      name: t(`${KEY}.NAME`, { site: originHost(origin) }),
      inbox_id: chosenInbox.value,
      allowed_origins: [origin],
    });
    emit('created', data.payload);
    dialog.value?.close();
  } catch {
    failed.value = true;
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="$t(`${KEY}.TITLE`)"
    :description="$t(`${KEY}.TEXT`)"
    :confirm-button-label="$t(`${KEY}.SAVE`)"
    :cancel-button-label="$t(`${KEY}.CANCEL`)"
    :disable-confirm-button="!canSave"
    :is-loading="saving"
    @confirm="save"
  >
    <div data-site-link-dialog class="flex flex-col gap-4">
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${KEY}.ADDRESS`) }}
        </span>
        <input
          v-model="address"
          data-site-link-address
          type="text"
          inputmode="url"
          autocomplete="url"
          :placeholder="$t(`${KEY}.ADDRESS_PLACEHOLDER`)"
          :aria-invalid="showError ? 'true' : undefined"
          class="px-3 text-sm border border-solid rounded-xl min-h-11 bg-n-solid-1 text-n-slate-12"
          :class="showError ? 'border-n-ruby-8' : 'border-n-weak'"
          @blur="touched = true"
          @keydown.enter.prevent="save"
        />
        <span
          class="text-xs"
          :class="showError ? 'text-n-ruby-11' : 'text-n-slate-11'"
        >
          {{
            showError ? $t(`${KEY}.ADDRESS_ERROR`) : $t(`${KEY}.ADDRESS_HINT`)
          }}
        </span>
      </label>
      <p
        v-if="!inboxOptions.length"
        data-site-link-no-whatsapp
        class="m-0 text-sm text-n-amber-11"
      >
        {{ $t(`${KEY}.NO_WHATSAPP`) }}
      </p>
      <div v-if="inboxOptions.length > 1" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${KEY}.WHATSAPP`) }}
        </span>
        <ChoiceSelect
          v-model="inboxId"
          :options="inboxOptions"
          :aria-label="$t(`${KEY}.WHATSAPP`)"
          :placeholder="$t(`${KEY}.WHATSAPP_PLACEHOLDER`)"
        />
      </div>
      <p v-if="failed" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ $t(`${KEY}.ERROR`) }}
      </p>
    </div>
  </Dialog>
</template>
