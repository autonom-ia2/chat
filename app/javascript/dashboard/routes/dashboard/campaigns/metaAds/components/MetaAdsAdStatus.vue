<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { mudarStatus } from '../gestaoDoAnuncio';

// Anúncios da Meta (#2161): no topo do anúncio, se ele está no ar ou pausado e o botão para mudar. Pausar é sempre
// gesto da pessoa, com confirmação; o consultor só sugere. Quem não pode mexer (só vê, ou modo parceiro) vê a
// situação sem o botão. Token sem permissão de mudar: a frase diz como liberar, sem esconder.
const props = defineProps({
  adId: { type: String, required: true },
  adName: { type: String, default: '' },
  gestao: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const dialog = ref(null);
const saving = ref(false);

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS';

// O botão mexe na situação do próprio anúncio. "No ar" só quando a entrega também está ativa: anúncio ativo com a
// campanha ou o conjunto pausado (ou em análise, recusado…) fica "Fora do ar", e pausar continua valendo.
const active = computed(() => props.gestao.status === 'ACTIVE');
const badge = computed(() => {
  if (!active.value) return 'PAUSED';
  return props.gestao.effective_status === 'ACTIVE' ? 'ACTIVE' : 'OFF';
});
const action = computed(() => (active.value ? 'PAUSE' : 'ACTIVATE'));
const showButton = computed(
  () =>
    props.canManage &&
    props.gestao.can_change &&
    ['ACTIVE', 'PAUSED'].includes(props.gestao.status)
);
const showLoginHint = computed(
  () => props.canManage && props.gestao.needs_login
);

const confirm = async () => {
  saving.value = true;
  const next = active.value ? 'PAUSED' : 'ACTIVE';
  try {
    await mudarStatus(props.adId, next);
    emit('changed', next);
    dialog.value?.close();
    useAlert(t(`${KEY}.${action.value}_DONE`));
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(t(`${KEY}.${code === 'cannot_change' ? 'NEEDS_LOGIN' : 'ERROR'}`));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div
    data-ad-status
    :data-status="badge"
    class="relative flex flex-wrap items-center gap-3 pt-1"
  >
    <span
      data-ad-status-badge
      class="inline-flex min-h-8 items-center gap-2 rounded-full px-3 text-sm font-medium"
      :class="
        badge === 'ACTIVE'
          ? 'bg-n-teal-9/20 text-white'
          : 'bg-white/10 text-white/80'
      "
    >
      <span
        class="size-2 rounded-full"
        :class="badge === 'ACTIVE' ? 'bg-n-teal-9' : 'bg-white/50'"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.${badge}`) }}
    </span>
    <button
      v-if="showButton"
      type="button"
      data-ad-status-toggle
      class="inline-flex min-h-11 items-center gap-2 rounded-lg border-0 bg-white px-4 text-sm font-520 text-n-heroi hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
      @click="dialog?.open()"
    >
      <span
        :class="active ? 'i-lucide-pause' : 'i-lucide-play'"
        class="size-4"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.${action}`) }}
    </button>
    <p
      v-else-if="showLoginHint"
      data-ad-status-login
      class="m-0 text-sm text-white/75"
    >
      {{ $t(`${KEY}.NEEDS_LOGIN`) }}
    </p>

    <Dialog
      ref="dialog"
      type="alert"
      :title="$t(`${KEY}.${action}_TITLE`, { name: adName })"
      :description="$t(`${KEY}.${action}_HINT`)"
      :confirm-button-label="$t(`${KEY}.${action}`)"
      :cancel-button-label="$t(`${KEY}.CANCEL`)"
      :is-loading="saving"
      @confirm="confirm"
    />
  </div>
</template>
