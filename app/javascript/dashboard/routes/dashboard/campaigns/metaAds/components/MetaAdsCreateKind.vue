<script setup>
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';
// Anúncios da Meta (#2198): a primeira pergunta do Gerenciador simples. Só os tipos que o servidor oferece (`kinds`
// das opções). Cada cartão diz o que é e o que acontece; tocar já escolhe e segue. O que não dá nesta conta aparece apagado,
// com o motivo (só o ícone e o título apagados; o motivo em cor cheia) e, quando é com o suporte, o link para a Ajuda.
// Cartão apagado não é botão: dentro dele vai o link.
const props = defineProps({
  modelValue: { type: String, default: null },
  // Tipos que o servidor oferece: ['ad', 'post'] (#2339).
  kinds: { type: Array, default: () => [] },
  // { ad: 'NO_DESTINATION' }: o tipo e o motivo de não dar.
  unavailable: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['choose']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.KIND';
const KINDS = [
  { value: 'ad', icon: 'i-lucide-megaphone' },
  { value: 'post', icon: 'i-lucide-rocket' },
];
const offered = computed(() =>
  KINDS.filter(option => props.kinds.includes(option.value))
);

const choose = value => {
  if (props.unavailable[value]) return;
  emit('choose', value);
};
</script>

<template>
  <div
    class="grid grid-cols-1 gap-3 md:grid-cols-3"
    role="radiogroup"
    :aria-label="$t(`${KEY}.TITLE`)"
  >
    <component
      :is="unavailable[option.value] ? 'div' : 'button'"
      v-for="option in offered"
      :key="option.value"
      :type="unavailable[option.value] ? undefined : 'button'"
      role="radio"
      :aria-checked="modelValue === option.value"
      :aria-disabled="Boolean(unavailable[option.value]) || undefined"
      :data-create-kind="option.value"
      class="flex min-h-11 flex-col items-start gap-2 rounded-2xl border-0 p-5 text-start transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        modelValue === option.value
          ? 'bg-n-brand/10 ring-2 ring-n-brand'
          : 'bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-strong'
      "
      @click="choose(option.value)"
    >
      <span
        :class="[
          option.icon,
          unavailable[option.value] ? 'text-n-slate-10' : 'text-n-brand',
        ]"
        class="size-6"
        aria-hidden="true"
      />
      <span
        class="text-base font-semibold"
        :class="
          unavailable[option.value] ? 'text-n-slate-10' : 'text-n-slate-12'
        "
      >
        {{ $t(`${KEY}.${option.value.toUpperCase()}`) }}
      </span>
      <I18nT
        v-if="unavailable[option.value]"
        :keypath="`${KEY}.REASONS.${unavailable[option.value]}`"
        tag="span"
        :data-create-kind-unavailable="option.value"
        class="text-sm font-medium text-n-amber-11"
      >
        <template #support>
          <router-link
            :to="{ name: 'central_de_ajuda' }"
            data-create-kind-support
            class="text-n-amber-11 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          >
            {{ $t(`${KEY}.SUPPORT`) }}
          </router-link>
        </template>
      </I18nT>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t(`${KEY}.${option.value.toUpperCase()}_HINT`) }}
      </span>
    </component>
  </div>
</template>
