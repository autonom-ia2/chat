<script setup>
// One color of the identity (#1076): what it is for, the color, and "Alterar" to pick another
// (the system color picker or the code). The swatch shows the person's color, so it is :style.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { normalizeHex } from './brandColors';

const props = defineProps({
  role: { type: String, required: true },
  color: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['change']);

const NS = 'BRAND_KITS.COLORS';
const { t } = useI18n();
const isEditing = ref(false);
const draft = ref('');
const isInvalid = ref(false);

const open = () => {
  draft.value = props.color;
  isInvalid.value = false;
  isEditing.value = true;
};

const apply = value => {
  const hex = normalizeHex(value);
  isInvalid.value = !hex;
  if (hex) emit('change', hex);
};

const done = () => {
  apply(draft.value);
  if (!isInvalid.value) isEditing.value = false;
};
</script>

<template>
  <li class="flex flex-col gap-3 border-b border-n-weak py-3 last:border-0">
    <div class="flex items-center gap-3">
      <span
        class="size-9 shrink-0 rounded-lg border border-n-weak"
        :style="{ backgroundColor: color }"
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1">
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${NS}.ROLES.${role.toUpperCase()}.LABEL`) }}
        </p>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t(`${NS}.ROLES.${role.toUpperCase()}.HINT`) }}
        </p>
      </div>
      <code class="hidden font-mono text-xs text-n-slate-11 sm:inline">
        {{ color }}
      </code>
      <Button
        v-if="!disabled && !isEditing"
        :label="t(`${NS}.CHANGE`)"
        variant="outline"
        color="slate"
        size="sm"
        class="!min-h-11 !rounded-xl"
        :aria-label="
          t(`${NS}.CHANGE_ARIA`, {
            role: t(`${NS}.ROLES.${role.toUpperCase()}.LABEL`),
          })
        "
        :data-change="role"
        @click="open"
      />
    </div>
    <div
      v-if="isEditing"
      class="flex flex-wrap items-center gap-2 rounded-xl bg-n-alpha-1 p-3"
    >
      <input
        :value="color"
        type="color"
        class="size-11 cursor-pointer rounded-lg border border-n-weak bg-transparent p-1"
        :aria-label="t(`${NS}.PICK`)"
        @input="event => apply(event.target.value)"
      />
      <input
        v-model="draft"
        type="text"
        maxlength="7"
        class="m-0 h-11 w-28 rounded-lg border border-n-weak bg-n-solid-1 px-3 font-mono text-sm text-n-slate-12"
        :aria-label="t(`${NS}.CODE`)"
        :aria-invalid="isInvalid"
        @keydown.enter.prevent="done"
      />
      <Button
        :label="t(`${NS}.DONE`)"
        size="sm"
        class="!min-h-11 !rounded-xl"
        data-test="color-done"
        @click="done"
      />
      <p
        v-if="isInvalid"
        role="alert"
        class="m-0 w-full text-xs text-n-ruby-11"
      >
        {{ t(`${NS}.INVALID`) }}
      </p>
    </div>
  </li>
</template>
