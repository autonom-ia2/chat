<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { nomeDaAcao } from 'dashboard/helper/automacaoEmPortugues';

// #2413 — um passo que este formulário não oferece (o Decisor, change_status, CRM ou SLA desligados).
// Fica travado e volta intacto no salvar; a pessoa só pode removê-lo.
const props = defineProps({
  actionName: {
    type: String,
    required: true,
  },
  errorMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['removeAction']);

const { t } = useI18n();

const nome = computed(() => nomeDaAcao(props.actionName, t));
</script>

<template>
  <li class="list-none py-2 first:pt-0 last:pb-0">
    <div class="flex items-center gap-2">
      <div
        class="flex items-center flex-1 min-w-0 gap-2 px-3 py-1.5 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak dark:outline-n-strong"
      >
        <span
          class="i-lucide-lock size-4 flex-shrink-0 text-n-slate-10"
          aria-hidden="true"
        />
        <span class="text-sm truncate text-n-slate-12">{{ nome }}</span>
        <span class="text-xs truncate text-n-slate-10">
          {{ $t('AUTOMATION.LOCKED_ACTION.HINT') }}
        </span>
      </div>
      <NextButton
        sm
        solid
        slate
        icon="i-lucide-trash"
        class="flex-shrink-0"
        :aria-label="$t('AUTOMATION.LOCKED_ACTION.REMOVE')"
        @click="emit('removeAction')"
      />
    </div>
    <span v-if="errorMessage" class="text-sm text-n-ruby-11">
      {{ errorMessage }}
    </span>
  </li>
</template>
