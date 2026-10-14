<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { LOGO_DARK_MODES, logoAlignOf, logoDarkModeOf } from '../helpers/brand';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';

// Cabeçalho com a cara da empresa (RA-20): logo, foto, nome, título. Sem logo ou foto (ou imagem quebrada),
// mostra a inicial na cor da marca; nada quebra.
//
// Logo (#1289): fica numa caixa de 56 px de altura e a imagem tem dois limites, 56 px de altura e 192 px de largura;
// ela só encolhe até caber inteira (`object-contain`), sem esticar nem cortar. Logo deitada esbarra na largura (uma
// 4:1 fica com 48 px de altura, 20% a mais que os 40 px de antes); quadrada e em pé esbarram na altura e ficam um
// pouco maiores, para não sumirem ao lado de uma deitada. A pessoa escolhe de que lado ela fica
// (`brand.logo_align`); o padrão é a esquerda. A prévia do painel usa este mesmo componente.
//
// Logo por tema (#1295), só com CSS (as variáveis `--bk-*` mudam com o tema, sem script): com uma imagem própria
// para o escuro, as duas ficam no HTML e cada tema mostra a sua; quando a logo de sempre já se lê no escuro, é uma
// imagem só; sem versão para o escuro, a logo de sempre ganha uma placa clara no tema escuro (no claro a placa é
// transparente e sem margem: nada muda). Se a imagem do escuro não carregar, vale a placa. Fora de um tema (as
// variáveis não existem), vale o claro.
const props = defineProps({
  page: { type: Object, required: true },
  subtitle: { type: String, default: '' },
});

const LOGO_SIDES = {
  left: 'justify-start',
  center: 'justify-center',
  right: 'justify-end',
};
const LOGO_IMAGE =
  'h-auto max-h-full w-auto min-w-0 max-w-[min(12rem,100%)] object-contain';
const LIGHT_ONLY = '[display:var(--bk-light-only,block)]';
const DARK_ONLY = '[display:var(--bk-dark-only,none)]';
const LOGO_LOOKS = {
  [LOGO_DARK_MODES.OWN]: LIGHT_ONLY,
  [LOGO_DARK_MODES.SAME]: 'block',
  [LOGO_DARK_MODES.PLATE]:
    'block rounded-lg bg-[var(--bk-plate)] p-[var(--bk-plate-pad)]',
};

const { t } = useI18n();
const flow = useFlow();
const logoFailed = ref(false);
const logoDarkFailed = ref(false);
const photoFailed = ref(false);

const imageUrl = value => safeAbsoluteUrl(value) || safeUrl(value);
const logoUrl = computed(() =>
  logoFailed.value ? null : imageUrl(props.page.brand?.logo_url)
);
const logoAlign = computed(() => logoAlignOf(props.page.brand?.logo_align));
const logoDarkUrl = computed(() =>
  logoDarkFailed.value ? null : imageUrl(props.page.brand?.logo_dark_url)
);
const logoDarkMode = computed(() =>
  logoDarkModeOf({
    darkUrl: logoDarkUrl.value,
    source: props.page.brand?.logo_dark_source,
  })
);
const hasOwnDarkLogo = computed(
  () => logoDarkMode.value === LOGO_DARK_MODES.OWN
);
const photoUrl = computed(() =>
  photoFailed.value
    ? null
    : imageUrl(props.page.brand?.photo_url || props.page.agent_photo_url)
);
const agentName = computed(() => props.page.agent_name || '');
const logoAlt = computed(() =>
  t('BOOKING_V2.HEADER.LOGO_ALT', {
    name: props.page.title || agentName.value,
  })
);
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
  () => props.page.brand?.logo_dark_url,
  () => {
    logoDarkFailed.value = false;
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
      :data-logo-dark="logoDarkMode"
      class="flex h-14 w-full items-center"
      :class="LOGO_SIDES[logoAlign]"
    >
      <img
        :src="logoUrl"
        :alt="logoAlt"
        :class="[LOGO_IMAGE, LOGO_LOOKS[logoDarkMode]]"
        @error="logoFailed = true"
      />
      <img
        v-if="hasOwnDarkLogo"
        data-logo-for-dark
        :src="logoDarkUrl"
        :alt="logoAlt"
        :class="[LOGO_IMAGE, DARK_ONLY]"
        @error="logoDarkFailed = true"
      />
    </div>
    <p v-if="headline" class="m-0 text-base font-medium text-bk-medium">
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
          class="m-0 text-lg font-semibold text-bk-strong [overflow-wrap:anywhere]"
        >
          {{ agentName || page.title }}
        </p>
        <p
          v-if="agentName && page.title"
          class="m-0 text-base text-bk-medium [overflow-wrap:anywhere]"
        >
          {{ page.title }}
        </p>
        <p
          v-if="subtitle || durationText"
          class="m-0 text-base text-bk-soft first-letter:uppercase"
        >
          {{ subtitle || durationText }}
        </p>
      </div>
    </div>
  </header>
</template>
