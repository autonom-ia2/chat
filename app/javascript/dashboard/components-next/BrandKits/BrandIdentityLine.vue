<script setup>
// Nova campanha › Mensagem › E-mail (#1076): one line with the identity the e-mail will use —
// "Identidade: Hub2You (padrão) · Trocar · Gerenciar". Trocar picks another identity for this
// e-mail; Gerenciar opens Identidade visual and comes back (draft kept, like Público).
// Without any identity: one sentence and "Usar o meu site".
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { DOT } from 'dashboard/components-next/CampaignJourney/textMarks';
import { useBrandKits } from './useBrandKits';

const props = defineProps({
  kitId: { type: Number, default: null },
});

const emit = defineEmits(['change', 'manage']);

const NS = 'BRAND_KITS.LINE';
const { t } = useI18n();
const { kits, defaultKit, loaded, isAvailable, canManage, ensureKits } =
  useBrandKits();
const menuOpen = ref(false);

const kit = computed(
  () => kits.value.find(item => item.id === props.kitId) || defaultKit.value
);

const choose = item => {
  menuOpen.value = false;
  emit('change', item.is_default ? null : item.id);
};

onMounted(() => {
  if (isAvailable.value) ensureKits();
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="isAvailable && loaded"
    class="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-xl bg-n-alpha-1 px-3 py-1 text-sm"
    data-test="identity-line"
  >
    <template v-if="kit">
      <span class="text-n-slate-11">{{ t(`${NS}.LABEL`) }}</span>
      <span class="font-semibold text-n-slate-12">{{ kit.name }}</span>
      <span v-if="kit.is_default" class="text-n-slate-11">
        {{ t(`${NS}.DEFAULT`) }}
      </span>
      <span aria-hidden="true" class="text-n-slate-10">{{ DOT }}</span>
      <div v-on-click-outside="() => (menuOpen = false)" class="relative">
        <button
          type="button"
          class="min-h-11 px-1 font-semibold text-n-blue-11 hover:underline"
          :aria-expanded="menuOpen"
          aria-haspopup="menu"
          data-test="identity-line-change"
          @click="menuOpen = !menuOpen"
        >
          {{ t(`${NS}.CHANGE`) }}
        </button>
        <div
          v-if="menuOpen"
          role="menu"
          class="absolute start-0 top-full z-30 mt-1 w-64 rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-lg"
        >
          <button
            v-for="item in kits"
            :key="item.id"
            type="button"
            role="menuitemradio"
            :aria-checked="kit.id === item.id"
            class="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-start text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="choose(item)"
          >
            <span class="flex-1 truncate">{{ item.name }}</span>
            <span
              v-if="kit.id === item.id"
              class="i-lucide-check size-4 text-n-blue-11"
              aria-hidden="true"
            />
          </button>
        </div>
      </div>
      <span v-if="canManage" aria-hidden="true" class="text-n-slate-10">
        {{ DOT }}
      </span>
      <button
        v-if="canManage"
        type="button"
        class="min-h-11 px-1 font-semibold text-n-blue-11 hover:underline"
        data-test="identity-line-manage"
        @click="emit('manage', false)"
      >
        {{ t(`${NS}.MANAGE`) }}
      </button>
    </template>
    <template v-else-if="canManage">
      <span class="text-n-slate-11">{{ t('BRAND_KITS.NUDGE.TEXT') }}</span>
      <button
        type="button"
        class="min-h-11 px-1 font-semibold text-n-blue-11 hover:underline"
        data-test="identity-line-create"
        @click="emit('manage', true)"
      >
        {{ t('BRAND_KITS.NUDGE.ACTION') }}
      </button>
    </template>
  </div>
</template>
