<script setup>
import { computed, nextTick, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingImageUpload from './BookingImageUpload.vue';

// "Sua foto" no passo Sua marca (#1298): a foto de quem atende conversa com a
// foto do perfil.
// - Sem foto própria da página, o cartão mostra a foto que a página pública
//   já usa (a guardada na identidade ou a do perfil) e diz de onde ela vem.
// - Quem troca a própria foto e já tem foto no perfil escolhe, em dois
//   cartões, se a nova vale só nesta página ou também no perfil.
// - Quem não tem foto no perfil é avisado antes: a foto vai para os dois.
// - Quem monta a página de outra pessoa troca só a foto do agendamento; o
//   perfil alheio não muda (o servidor garante), e o cartão diz isso.
const props = defineProps({
  // A página como a API devolve: photo_url, host e photo_owner.
  page: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  error: { type: String, default: '' },
});

const emit = defineEmits(['upload']);
const { t } = useI18n();

const BUTTON =
  'inline-flex items-center justify-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
const CHOICES = [
  { key: 'page', i18n: 'ONLY_HERE', icon: 'i-lucide-calendar-check' },
  { key: 'profile', i18n: 'ALSO_PROFILE', icon: 'i-lucide-circle-user-round' },
];

// { name, mine, profile_url } de quem atende; nulo em página com um link por pessoa.
const owner = computed(() => props.page.photo_owner || null);
const savedUrl = computed(() => props.page.host?.booking_photo_url || '');
const profileUrl = computed(() => owner.value?.profile_url || '');
// A mesma ordem da página pública: foto da página, guardada, perfil.
const shownUrl = computed(
  () => props.page.photo_url || savedUrl.value || profileUrl.value
);

// De onde vem a foto que está aparecendo, quando não é da própria página.
const source = computed(() => {
  if (props.page.photo_url || !shownUrl.value) return null;
  if (savedUrl.value) return { key: 'USING_SAVED' };
  return owner.value.mine
    ? { key: 'USING_PROFILE_MINE' }
    : { key: 'USING_PROFILE_OTHER', name: owner.value.name };
});

// O que acontece com o perfil, dito antes de enviar.
const notice = computed(() => {
  if (!owner.value) return { key: 'SHARED_PAGE' };
  if (!owner.value.mine) return { key: 'OTHER_PERSON', name: owner.value.name };
  return profileUrl.value ? null : { key: 'GOES_TO_PROFILE' };
});

const pending = ref(null);
const choice = ref('page');
const choiceBox = useTemplateRef('choiceBox');
const card = useTemplateRef('card');
const titleId = useId();

const send = (file, applyToProfile) =>
  emit('upload', { kind: 'photo', file, applyToProfile });

const onPick = async file => {
  if (!owner.value?.mine) return send(file, false);
  if (!profileUrl.value) return send(file, true);
  pending.value = file;
  choice.value = 'page';
  await nextTick();
  return choiceBox.value?.focus();
};

// Fechou a pergunta: o foco volta para o botão de trocar a foto.
const closeChoice = async () => {
  pending.value = null;
  await nextTick();
  card.value?.querySelector('[data-upload]')?.focus();
};

// Grupo de escolha única no padrão WAI-ARIA: Tab para na opção marcada e as
// setas trocam (e marcam) a opção.
const moveChoice = async step => {
  const index = CHOICES.findIndex(option => option.key === choice.value);
  const next = CHOICES[(index + step + CHOICES.length) % CHOICES.length];
  choice.value = next.key;
  await nextTick();
  choiceBox.value?.querySelector(`[data-photo-target="${next.key}"]`)?.focus();
};

const confirmChoice = () => {
  send(pending.value, choice.value === 'profile');
  closeChoice();
};
</script>

<template>
  <div ref="card" data-photo class="flex flex-col gap-3">
    <BookingImageUpload
      round
      :label="t('BOOKING.LOOK.PHOTO')"
      :alt="t('BOOKING.LOOK.PHOTO_ALT')"
      :url="shownUrl"
      :busy="busy"
      :error="error"
      :hint="source ? t(`BOOKING.LOOK.PHOTO_CARD.${source.key}`, source) : ''"
      @pick="onPick"
    />
    <p
      v-if="notice && !pending"
      data-photo-notice
      class="flex items-start gap-2 m-0 text-base text-n-slate-11"
    >
      <span class="i-lucide-info mt-1 size-4 shrink-0" aria-hidden="true" />
      {{ t(`BOOKING.LOOK.PHOTO_CARD.${notice.key}`, notice) }}
    </p>
    <div
      v-if="pending"
      ref="choiceBox"
      data-photo-choice
      role="alertdialog"
      tabindex="-1"
      :aria-labelledby="titleId"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-blue-6 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @keydown.esc.stop="closeChoice"
    >
      <p :id="titleId" class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.LOOK.PHOTO_CARD.CHOICE_TITLE') }}
      </p>
      <div
        role="radiogroup"
        :aria-labelledby="titleId"
        class="grid gap-2"
        @keydown.down.prevent="moveChoice(1)"
        @keydown.right.prevent="moveChoice(1)"
        @keydown.up.prevent="moveChoice(-1)"
        @keydown.left.prevent="moveChoice(-1)"
      >
        <button
          v-for="option in CHOICES"
          :key="option.key"
          type="button"
          role="radio"
          :data-photo-target="option.key"
          :aria-checked="choice === option.key ? 'true' : 'false'"
          :tabindex="choice === option.key ? 0 : -1"
          class="flex items-center gap-3 min-h-14 px-4 py-2 rounded-xl text-base text-start font-medium text-n-slate-12 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            choice === option.key
              ? 'ring-2 ring-n-blue-9 bg-n-blue-2'
              : 'ring-1 ring-n-weak bg-n-solid-1 hover:ring-n-blue-7'
          "
          @click="choice = option.key"
        >
          <span
            class="size-5 shrink-0"
            :class="option.icon"
            aria-hidden="true"
          />
          {{ t(`BOOKING.LOOK.PHOTO_CARD.${option.i18n}`) }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-photo-choice-send
          :class="BUTTON"
          class="text-white bg-n-blue-9 ring-n-blue-9 hover:bg-n-blue-10"
          @click="confirmChoice"
        >
          {{ t('BOOKING.LOOK.PHOTO_CARD.SEND') }}
        </button>
        <button
          type="button"
          data-photo-choice-cancel
          :class="BUTTON"
          class="text-n-slate-12 bg-n-solid-1 ring-n-weak hover:ring-n-blue-7"
          @click="closeChoice"
        >
          {{ t('BOOKING.LOOK.PHOTO_CARD.CANCEL') }}
        </button>
      </div>
    </div>
  </div>
</template>
