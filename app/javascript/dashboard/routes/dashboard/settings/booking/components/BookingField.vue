<script setup>
import { useId } from 'vue';

// Campo de texto com rótulo visível ligado ao input (leitor de tela) e texto
// de 16 px. O aviso de erro fica ligado por aria-describedby.
defineProps({
  label: { type: String, required: true },
  placeholder: { type: String, default: '' },
  maxlength: { type: Number, default: 255 },
  type: { type: String, default: 'text' },
  error: { type: String, default: '' },
});

const model = defineModel({ type: String, default: '' });
const id = useId();
</script>

<template>
  <div class="flex flex-col gap-2">
    <label :for="id" class="text-base font-semibold text-n-slate-12">
      {{ label }}
    </label>
    <input
      :id="id"
      v-model="model"
      :type="type"
      :placeholder="placeholder"
      :maxlength="maxlength"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="error ? `${id}-error` : undefined"
      class="block w-full reset-base !mb-0 min-h-12 px-4 text-base rounded-xl border-0 bg-n-solid-1 text-n-slate-12 ring-1 ring-inset placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
      :class="error ? 'ring-n-ruby-8' : 'ring-n-weak'"
    />
    <p v-if="error" :id="`${id}-error`" class="m-0 text-base text-n-ruby-11">
      {{ error }}
    </p>
  </div>
</template>
