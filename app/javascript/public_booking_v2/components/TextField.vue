<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Campo de texto grande. `error` é a chave de tradução do erro: o erro fica ligado ao campo (aria-describedby) e quem
// avisa é o foco no campo, não um alerta por campo (um só alerta por vez na tela).

const props = defineProps({
  id: { type: String, required: true },
  label: { type: String, required: true },
  hint: { type: String, default: '' },
  error: { type: String, default: '' },
  type: { type: String, default: 'text' },
  autocomplete: { type: String, default: 'off' },
  inputmode: { type: String, default: undefined },
  required: { type: Boolean, default: false },
});

const model = defineModel({ type: String, default: '' });
const { t } = useI18n();
const errorText = computed(() => (props.error ? t(props.error) : ''));

const describedBy = computed(
  () =>
    [props.hint && `${props.id}-hint`, props.error && `${props.id}-error`]
      .filter(Boolean)
      .join(' ') || undefined
);
</script>

<template>
  <div class="flex flex-col gap-1">
    <label :for="id" class="text-base font-medium text-bk-body">
      {{ label }}
    </label>
    <input
      :id="id"
      v-model="model"
      :type="type"
      :autocomplete="autocomplete"
      :inputmode="inputmode"
      :required="required"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="describedBy"
      class="min-h-12 w-full rounded-xl border-2 bg-bk-field px-4 py-3 text-base text-bk-strong focus:border-[var(--brand)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
      :class="error ? 'border-bk-danger-line' : 'border-bk-line-field'"
    />
    <p v-if="hint" :id="`${id}-hint`" class="text-base text-bk-soft">
      {{ hint }}
    </p>
    <p
      v-if="error"
      :id="`${id}-error`"
      class="text-base font-medium text-bk-danger-text"
    >
      {{ errorText }}
    </p>
  </div>
</template>
