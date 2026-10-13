<script setup>
// A lista de opções sempre aberta (decisão aprovada em 13/10/2026): seções com título, opções com descrição e a
// opção que o cliente tocou marcada. Peça da bolha `types/Options.vue`; não é bolha por si.
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  // [{ title, options: [{ id, title, description }] }], já normalizadas como texto.
  sections: { type: Array, required: true },
  chosenId: { type: String, default: '' },
});

const isChosen = option =>
  Boolean(props.chosenId) && option.id === props.chosenId;
</script>

<template>
  <div
    class="rounded-lg border border-n-container bg-n-solid-3 overflow-hidden py-1"
  >
    <div
      v-for="(section, index) in sections"
      :key="index"
      :role="section.title ? 'group' : undefined"
      :aria-label="section.title || undefined"
    >
      <div
        v-if="section.title"
        aria-hidden="true"
        class="px-3 pt-2 pb-1 text-xs text-n-slate-11 break-words"
      >
        {{ section.title }}
      </div>
      <ul>
        <li
          v-for="(option, row) in section.options"
          :key="row"
          data-option-row
          class="flex items-start gap-2 px-3 py-2"
          :class="{ 'bg-n-alpha-2': isChosen(option) }"
        >
          <div class="flex-1 min-w-0">
            <div
              class="text-sm text-n-slate-12 break-words"
              :class="{ 'font-medium': isChosen(option) }"
            >
              {{ option.title }}
            </div>
            <div
              v-if="option.description"
              class="text-xs text-n-slate-11 break-words"
            >
              {{ option.description }}
            </div>
          </div>
          <Icon
            v-if="isChosen(option)"
            icon="i-lucide-check"
            class="size-4 mt-0.5 flex-shrink-0 text-n-teal-11"
          />
        </li>
      </ul>
    </div>
  </div>
</template>
