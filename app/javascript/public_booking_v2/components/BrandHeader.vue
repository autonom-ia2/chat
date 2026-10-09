<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';

// Cabeçalho com a cara da empresa (RA-20): logo, foto, nome, título. Sem logo ou foto (ou imagem quebrada),
// mostra a inicial na cor da marca; nada quebra.
const props = defineProps({
  page: { type: Object, required: true },
  subtitle: { type: String, default: '' },
});

const { t } = useI18n();
const flow = useFlow();
const logoFailed = ref(false);
const photoFailed = ref(false);

const imageUrl = value => safeAbsoluteUrl(value) || safeUrl(value);
const logoUrl = computed(() =>
  logoFailed.value ? null : imageUrl(props.page.brand?.logo_url)
);
const photoUrl = computed(() =>
  photoFailed.value
    ? null
    : imageUrl(props.page.brand?.photo_url || props.page.agent_photo_url)
);
const agentName = computed(() => props.page.agent_name || '');
const initial = computed(
  () => (agentName.value || props.page.title || '?').trim().charAt(0) || '?'
);
const headline = computed(() => props.page.brand?.headline || '');
// A duração escolhida pela pessoa (pode ser outra que a principal da página).
const minutes = computed(
  () => flow?.duration?.value || props.page.duration_minutes
);
const durationText = computed(() =>
  minutes.value ? t('BOOKING_V2.DURATION', { minutes: minutes.value }) : ''
);
</script>

<template>
  <header class="flex flex-col gap-4">
    <img
      v-if="logoUrl"
      :src="logoUrl"
      :alt="t('BOOKING_V2.HEADER.LOGO_ALT', { name: page.title || agentName })"
      class="h-10 w-auto max-w-[60%] self-start object-contain"
      @error="logoFailed = true"
    />
    <p v-if="headline" class="text-base font-medium text-slate-700">
      {{ headline }}
    </p>
    <div class="flex items-center gap-3">
      <img
        v-if="photoUrl"
        :src="photoUrl"
        :alt="t('BOOKING_V2.HEADER.PHOTO_ALT', { name: agentName })"
        class="size-14 shrink-0 rounded-full object-cover"
        @error="photoFailed = true"
      />
      <span
        v-else
        aria-hidden="true"
        class="flex size-14 shrink-0 items-center justify-center rounded-full bg-[var(--brand)] text-xl font-bold uppercase text-white"
      >
        {{ initial }}
      </span>
      <div class="flex min-w-0 flex-col">
        <p
          class="text-lg font-semibold text-slate-900 [overflow-wrap:anywhere]"
        >
          {{ agentName || page.title }}
        </p>
        <p
          v-if="agentName && page.title"
          class="text-base text-slate-700 [overflow-wrap:anywhere]"
        >
          {{ page.title }}
        </p>
        <p
          v-if="subtitle || durationText"
          class="text-base text-slate-600 first-letter:uppercase"
        >
          {{ subtitle || durationText }}
        </p>
      </div>
    </div>
  </header>
</template>
