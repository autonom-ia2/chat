<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { guestInitials, isValidEmail, normalizeEmail } from './meetingGuests';

// Convidados da reunião do Google/Microsoft: os selos e o campo para somar
// e-mails. Enter, vírgula e ponto e vírgula confirmam (como no Gmail); sair do
// campo com um e-mail válido também. Quem usa chama `commit()` antes de enviar,
// para nada do que foi digitado se perder.
const props = defineProps({
  // "Adicione um convidado" quando a pessoa tentou marcar sem nenhum.
  requiredError: { type: String, default: '' },
});
const guests = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();
const S = 'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER';
const email = ref('');
const emailError = ref('');

const has = valor =>
  guests.value.some(guest => normalizeEmail(guest.email) === valor);
const push = valor => {
  guests.value = [
    ...guests.value,
    { email: valor, name: '', source: 'external' },
  ];
};

const addGuest = () => {
  const valor = normalizeEmail(email.value);
  emailError.value = '';
  if (!valor) {
    emailError.value = t(`${S}.GUEST_EMAIL_REQUIRED`);
    return;
  }
  if (!isValidEmail(valor)) {
    emailError.value = t(`${S}.GUEST_EMAIL_INVALID`);
    return;
  }
  if (has(valor)) {
    emailError.value = t(`${S}.GUEST_EMAIL_DUPLICATE`);
    return;
  }
  push(valor);
  email.value = '';
};

// Keys that confirm the typed email as a chip — captured on keydown (before
// the browser's default submit/focus shift) so Enter no longer "leaks" into the
// form and pops the mailbox combo open.
const COMMIT_KEYS = ['Enter', ',', ';'];
const onKeydown = event => {
  if (!COMMIT_KEYS.includes(event.key)) return;
  event.preventDefault();
  event.stopPropagation();
  addGuest();
};

// Leaving the field with a valid, unique email commits it silently.
const onBlur = () => {
  const valor = normalizeEmail(email.value);
  if (!valor || !isValidEmail(valor)) return;
  if (!has(valor)) push(valor);
  email.value = '';
  emailError.value = '';
};

// Safety net on submit: false (with the error) only when the leftover text is
// a non-empty INVALID email.
const commit = () => {
  emailError.value = '';
  const raw = email.value.trim();
  if (!raw) return true;
  const valor = normalizeEmail(raw);
  if (!isValidEmail(valor)) {
    emailError.value = t(`${S}.GUEST_EMAIL_INVALID`);
    return false;
  }
  if (!has(valor)) push(valor);
  email.value = '';
  return true;
};

const reset = () => {
  email.value = '';
  emailError.value = '';
};

const removeGuest = valor => {
  const alvo = normalizeEmail(valor);
  guests.value = guests.value.filter(
    guest => normalizeEmail(guest.email) !== alvo
  );
};

defineExpose({ commit, reset });
// O erro do que está sendo digitado vem antes do "falta um convidado".
const message = computed(() => emailError.value || props.requiredError);
</script>

<template>
  <fieldset class="flex flex-col gap-2">
    <legend
      class="mb-0 text-xs font-medium text-n-slate-11 after:ml-0.5 after:text-n-ruby-11 after:content-['*']"
    >
      {{ t(`${S}.GUESTS_LABEL`) }}
    </legend>

    <div class="flex flex-wrap gap-2">
      <span
        v-for="guest in guests"
        :key="guest.email"
        class="inline-flex max-w-full items-center gap-2 rounded-lg bg-n-alpha-1 px-2 py-1 text-xs text-n-slate-12 outline outline-1 outline-n-weak"
      >
        <span
          class="flex size-5 flex-shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-[10px] font-semibold uppercase text-n-slate-11"
        >
          {{ guestInitials(guest) }}
        </span>
        <span class="min-w-0 truncate">{{ guest.name || guest.email }}</span>
        <span
          class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[10px] text-n-slate-11"
        >
          {{
            guest.source === 'contact'
              ? t(`${S}.CONTACT_TAG`)
              : t(`${S}.GUEST_TAG`)
          }}
        </span>
        <button
          type="button"
          class="relative grid size-5 flex-shrink-0 place-items-center rounded-md text-n-slate-10 before:absolute before:-inset-3 hover:text-n-ruby-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t(`${S}.REMOVE_GUEST`, { email: guest.email })"
          @click="removeGuest(guest.email)"
        >
          <span class="i-lucide-x size-3.5" aria-hidden="true" />
        </button>
      </span>
    </div>

    <div class="flex items-start gap-2" @keydown="onKeydown">
      <Input
        v-model="email"
        type="email"
        :placeholder="t(`${S}.GUEST_EMAIL_PLACEHOLDER`)"
        :message="message"
        :message-type="message ? 'error' : 'info'"
        autocomplete="email"
        class="min-w-0 flex-1"
        @blur="onBlur"
      />
      <Button
        type="button"
        variant="faded"
        color="slate"
        size="md"
        icon="i-lucide-plus"
        :label="t(`${S}.ADD_GUEST`)"
        @mousedown.prevent
        @click="addGuest"
      />
    </div>

    <p class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-10">
      <span class="i-lucide-corner-down-left size-3.5" aria-hidden="true" />
      <span>{{ t(`${S}.GUEST_HINT`) }}</span>
    </p>
  </fieldset>
</template>
