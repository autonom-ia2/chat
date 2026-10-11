<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { logoAlignOf } from '../helpers/brand';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';

// Cabeçalho com a cara da empresa (RA-20): logo, foto, nome, título. Sem logo ou foto (ou imagem quebrada),
// mostra a inicial na cor da marca; nada quebra.
//
// Logo (#1289): fica numa caixa de 56 px de altura e a imagem tem dois limites, 56 px de altura e 192 px de largura;
// ela só encolhe até caber inteira (`object-contain`), sem esticar nem cortar. Logo deitada esbarra na largura (uma
// 4:1 fica com 48 px de altura, 20% a mais que os 40 px de antes); quadrada e em pé esbarram na altura e ficam um
// pouco maiores, para não sumirem ao lado de uma deitada. A pessoa escolhe de que lado ela fica
// (`brand.logo_align`); o padrão é a esquerda. A prévia do painel usa este mesmo componente.
const props = defineProps({
  page: { type: Object, required: true },
  subtitle: { type: String, default: '' },
});

const LOGO_SIDES = {
  left: 'justify-start',
  center: 'justify-center',
  right: 'justify-end',
};

const { t } = useI18n();
const flow = useFlow();
const logoFailed = ref(false);
const photoFailed = ref(false);

const imageUrl = value => safeAbsoluteUrl(value) || safeUrl(value);
const logoUrl = computed(() =>
  logoFailed.value ? null : imageUrl(props.page.brand?.logo_url)
);
const logoAlign = computed(() => logoAlignOf(props.page.brand?.logo_align));
const photoUrl = computed(() =>
  photoFailed.value
    ? null
    : imageUrl(props.page.brand?.photo_url || props.page.agent_photo_url)
);
const agentName = computed(() => props.page.agent_name || '');
const initial = computed(
  () => (agentName.value || props.page.title || '?').trim().charAt(0) || '?'
);
// Imagem trocada (a prévia do painel troca na hora): a nova ganha a chance de carregar.
watch(
  () => props.page.brand?.logo_url,
  () => {
    logoFailed.value = false;
  }
);
watch(
  () => props.page.brand?.photo_url || props.page.agent_photo_url,
  () => {
    photoFailed.value = false;
  }
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
  <header data-brand-header class="flex flex-col gap-4">
    <div
      v-if="logoUrl"
      data-logo-box
      :data-logo-align="logoAlign"
      class="flex h-14 w-full items-center"
      :class="LOGO_SIDES[logoAlign]"
    >
      <img
        :src="logoUrl"
        :alt="
          t('BOOKING_V2.HEADER.LOGO_ALT', { name: page.title || agentName })
        "
        class="block h-auto max-h-full w-auto min-w-0 max-w-[min(12rem,100%)] object-contain"
        @error="logoFailed = true"
      />
    </div>
    <p v-if="headline" class="m-0 text-base font-medium text-slate-700">
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
        class="flex size-14 shrink-0 items-center justify-center rounded-full bg-[var(--brand-fill)] text-xl font-bold uppercase text-[var(--brand-on)] ring-1 ring-inset ring-[var(--brand)]"
      >
        {{ initial }}
      </span>
      <div class="flex min-w-0 flex-col">
        <p
          class="m-0 text-lg font-semibold text-slate-900 [overflow-wrap:anywhere]"
        >
          {{ agentName || page.title }}
        </p>
        <p
          v-if="agentName && page.title"
          class="m-0 text-base text-slate-700 [overflow-wrap:anywhere]"
        >
          {{ page.title }}
        </p>
        <p
          v-if="subtitle || durationText"
          class="m-0 text-base text-slate-600 first-letter:uppercase"
        >
          {{ subtitle || durationText }}
        </p>
      </div>
    </div>
  </header>
</template>
