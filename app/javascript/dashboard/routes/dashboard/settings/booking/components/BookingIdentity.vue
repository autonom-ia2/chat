<script setup>
import { computed, nextTick, ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

// Identidade salva da conta (#1289), em volta dos campos do passo Sua marca:
// em cima, "Usar a identidade salva" (só quando há uma); embaixo, "Salvar como
// identidade da conta" (só para o administrador: grava na conta). Quem salva
// uma vez não sobe logo, foto e cor de novo: as páginas novas já nascem assim.
//
// Usar a identidade troca a marca desta página, inclusive o que a pessoa
// acabou de mexer e ainda não salvou: por isso pede confirmação aqui mesmo,
// como o Excluir do cartão da página.
const props = defineProps({
  // { saved, color, logo_align, headline, logo_url, photo_url }
  identity: { type: Object, required: true },
  canSave: { type: Boolean, default: false },
  // Esta gravação guarda a foto? (Página com uma pessoa só e foto enviada.)
  savesPhoto: { type: Boolean, default: false },
  // 'applied' | 'saved' | null
  state: { type: String, default: null },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['apply', 'save']);
const { t } = useI18n();

const BUTTON =
  'inline-flex items-center justify-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60';
const PLAIN = 'text-n-slate-12 bg-n-solid-1 ring-n-weak hover:ring-n-blue-7';

const confirming = ref(false);
const confirmBox = useTemplateRef('confirmBox');
const useButton = useTemplateRef('useButton');
const confirmTextId = useId();

const askApply = async () => {
  confirming.value = true;
  await nextTick();
  confirmBox.value?.focus();
};

// Fechou a pergunta (Sim, Não ou Esc): o foco volta para o botão que a abriu.
const closeConfirm = async () => {
  confirming.value = false;
  await nextTick();
  useButton.value?.focus();
};

// "Sim": o botão fica desligado enquanto a identidade é aplicada, então o
// foco só volta para ele quando termina.
const refocusWhenDone = ref(false);
const confirmApply = () => {
  confirming.value = false;
  refocusWhenDone.value = true;
  emit('apply');
};
watch(
  () => props.busy,
  async busy => {
    if (busy || !refocusWhenDone.value) return;
    refocusWhenDone.value = false;
    await nextTick();
    useButton.value?.focus();
  }
);

// Diz o que foi guardado: a foto é de cada pessoa e só entra quando a página
// tem uma pessoa só e uma foto enviada.
const notice = computed(() => {
  if (props.state === 'applied') return 'APPLIED';
  if (props.state !== 'saved') return null;
  return props.savesPhoto ? 'SAVED' : 'SAVED_NO_PHOTO';
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div
      v-if="identity.saved"
      data-identity-saved
      class="flex flex-col gap-4 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center min-w-0 gap-3">
          <span
            v-if="identity.logo_url"
            class="grid place-items-center h-12 w-20 shrink-0 rounded-lg bg-white ring-1 ring-inset ring-n-weak"
          >
            <img
              :src="identity.logo_url"
              :alt="t('BOOKING.LOOK.LOGO_ALT')"
              class="object-contain w-[4.5rem] h-10"
            />
          </span>
          <div class="flex flex-col min-w-0 gap-0.5">
            <p class="m-0 text-base font-semibold text-n-slate-12">
              {{ t('BOOKING.LOOK.IDENTITY.SAVED_TITLE') }}
            </p>
            <p class="m-0 text-base text-n-slate-11">
              {{ t('BOOKING.LOOK.IDENTITY.SAVED_TEXT') }}
            </p>
          </div>
        </div>
        <button
          v-if="!confirming"
          ref="useButton"
          type="button"
          data-use-identity
          :disabled="busy"
          :class="[BUTTON, PLAIN]"
          @click="askApply"
        >
          <span class="i-lucide-wand-sparkles size-4" aria-hidden="true" />
          {{ t('BOOKING.LOOK.IDENTITY.USE') }}
        </button>
      </div>
      <div
        v-if="confirming"
        ref="confirmBox"
        data-identity-confirm
        role="alertdialog"
        tabindex="-1"
        :aria-label="t('BOOKING.LOOK.IDENTITY.USE')"
        :aria-describedby="confirmTextId"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @keydown.esc.stop="closeConfirm"
      >
        <p
          :id="confirmTextId"
          class="m-0 text-base font-medium text-n-amber-12"
        >
          {{ t('BOOKING.LOOK.IDENTITY.CONFIRM') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            data-identity-confirm-yes
            :class="BUTTON"
            class="text-white bg-n-blue-9 ring-n-blue-9 hover:bg-n-blue-10"
            @click="confirmApply"
          >
            {{ t('BOOKING.LOOK.IDENTITY.CONFIRM_YES') }}
          </button>
          <button
            type="button"
            data-identity-confirm-no
            :class="[BUTTON, PLAIN]"
            @click="closeConfirm"
          >
            {{ t('BOOKING.LOOK.IDENTITY.CONFIRM_NO') }}
          </button>
        </div>
      </div>
      <p
        v-if="notice === 'APPLIED'"
        data-identity-notice
        role="status"
        class="m-0 text-base text-n-teal-11"
      >
        {{ t('BOOKING.LOOK.IDENTITY.APPLIED') }}
      </p>
    </div>

    <slot />

    <div
      v-if="canSave"
      class="flex flex-col gap-3 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.LOOK.IDENTITY.SAVE_HINT') }}
      </p>
      <button
        type="button"
        data-save-identity
        :disabled="busy"
        class="self-start"
        :class="[BUTTON, PLAIN]"
        @click="emit('save')"
      >
        <span
          class="size-4"
          :class="
            busy ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-bookmark'
          "
          aria-hidden="true"
        />
        {{ t('BOOKING.LOOK.IDENTITY.SAVE') }}
      </button>
      <p
        v-if="notice && notice !== 'APPLIED'"
        data-identity-notice
        role="status"
        class="m-0 text-base text-n-teal-11"
      >
        {{ t(`BOOKING.LOOK.IDENTITY.${notice}`) }}
      </p>
    </div>
  </div>
</template>
