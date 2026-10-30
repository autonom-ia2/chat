<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  DESTINATION_ICONS,
  SITE_ACTIONS,
  siteValido,
  textoDaOferta,
} from '../anuncioNovo';
import { CAROUSEL_DESTINATIONS } from '../midiaDoAnuncio';

// Anúncios da Meta (#2198), anúncio novo: para onde vai quem toca, numa linha no topo da tela da foto ("Quem tocar
// vai para: WhatsApp · Trocar"). O WhatsApp já vem marcado; trocar abre as outras opções ali mesmo, sem passo a
// mais. Opção que não dá agora aparece apagada, com o motivo. Só aparece o destino que a chamada real já confirmou
// para a conta (`destinations` das opções). Site pede o endereço (sem precisar do https://) e o texto do botão.
const props = defineProps({
  phone: { type: String, default: '' },
  hasNumber: { type: Boolean, default: true },
  // Conta profissional do Instagram ligada à Página: { username } ou null.
  instagram: { type: Object, default: null },
  // Destinos confirmados para a conta, na ordem da tela.
  destinations: { type: Array, required: true },
});

const draft = defineModel({ type: Object, required: true });

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.DESTINATION';
const open = ref(false);

const isCarousel = computed(() => draft.value.more_media.length > 0);

// Por que uma opção não dá agora; '' quando dá.
const reasonFor = option => {
  if (option === 'WHATSAPP' && !props.hasNumber) return 'NO_NUMBER';
  if (option === 'INSTAGRAM_DIRECT' && !props.instagram) return 'NO_INSTAGRAM';
  if (isCarousel.value && !CAROUSEL_DESTINATIONS.includes(option)) {
    return 'CAROUSEL';
  }
  return '';
};

const labelFor = option => {
  if (option === 'WHATSAPP' && props.phone) {
    return t(`${KEY}.CURRENT_WHATSAPP`, { phone: props.phone });
  }
  if (option === 'INSTAGRAM_DIRECT' && props.instagram) {
    return t(`${KEY}.CURRENT_INSTAGRAM_DIRECT`, {
      username: props.instagram.username,
    });
  }
  return t(`${KEY}.OPTIONS.${option}`);
};

// O texto montado do que a pessoa vende acompanha o destino ("Chame no Messenger…"), até ela mexer no texto.
const choose = option => {
  if (reasonFor(option)) return;
  const current = draft.value;
  draft.value = {
    ...current,
    destination: option,
    text: current.text_edited
      ? current.text
      : textoDaOferta(t, current.offer, option),
  };
  open.value = false;
};

const siteError = computed(() =>
  draft.value.site_url && !siteValido(draft.value.site_url)
    ? t(`${KEY}.SITE_URL_ERROR`)
    : ''
);
</script>

<template>
  <div
    data-create-destination
    class="flex min-w-0 flex-col gap-3 rounded-2xl bg-n-alpha-1 p-4"
  >
    <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
      <span
        :class="DESTINATION_ICONS[draft.destination]"
        class="size-5 shrink-0 text-n-brand"
        aria-hidden="true"
      />
      <p class="m-0 min-w-0 flex-1 text-sm text-n-slate-11">
        {{ $t(`${KEY}.GOES_TO`) }}
        <span
          data-create-destination-current
          class="font-semibold text-n-slate-12"
        >
          {{ labelFor(draft.destination) }}
        </span>
      </p>
      <button
        type="button"
        data-create-destination-change
        :aria-expanded="open"
        class="inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-lg border-0 bg-transparent px-3 text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="open = !open"
      >
        {{ $t(`${KEY}.CHANGE`) }}
        <span
          :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4"
          aria-hidden="true"
        />
      </button>
    </div>

    <div
      v-if="open"
      role="radiogroup"
      :aria-label="$t(`${KEY}.GOES_TO`)"
      class="grid grid-cols-1 gap-2 sm:grid-cols-2"
    >
      <button
        v-for="option in destinations"
        :key="option"
        type="button"
        role="radio"
        :aria-checked="draft.destination === option"
        :aria-disabled="Boolean(reasonFor(option)) || undefined"
        :data-create-destination-option="option"
        class="flex min-h-11 items-start gap-3 rounded-xl border-0 p-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="[
          draft.destination === option
            ? 'bg-n-brand/10 ring-2 ring-n-brand'
            : 'bg-n-solid-1 ring-1 ring-n-weak',
          reasonFor(option) ? 'cursor-not-allowed opacity-60' : '',
        ]"
        @click="choose(option)"
      >
        <span
          :class="DESTINATION_ICONS[option]"
          class="mt-0.5 size-5 shrink-0 text-n-brand"
          aria-hidden="true"
        />
        <span class="flex min-w-0 flex-col gap-0.5">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ $t(`${KEY}.OPTIONS.${option}`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              reasonFor(option)
                ? $t(`${KEY}.REASONS.${reasonFor(option)}`)
                : $t(`${KEY}.HINTS.${option}`, {
                    username: instagram?.username,
                  })
            }}
          </span>
        </span>
      </button>
    </div>

    <template v-if="draft.destination === 'WEBSITE'">
      <Input
        :model-value="draft.site_url"
        data-create-site-url
        type="text"
        inputmode="url"
        autocapitalize="off"
        :label="$t(`${KEY}.SITE_URL`)"
        :placeholder="$t(`${KEY}.SITE_URL_PLACEHOLDER`)"
        :message="siteError"
        :message-type="siteError ? 'error' : 'info'"
        wrap-message
        @update:model-value="draft = { ...draft, site_url: $event.trim() }"
      />
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${KEY}.SITE_ACTION`) }}
        </span>
        <div
          role="radiogroup"
          :aria-label="$t(`${KEY}.SITE_ACTION`)"
          class="flex flex-wrap gap-2"
        >
          <button
            v-for="action in SITE_ACTIONS"
            :key="action"
            type="button"
            role="radio"
            :aria-checked="draft.site_action === action"
            :data-create-site-action="action"
            class="min-h-11 rounded-xl border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              draft.site_action === action
                ? 'bg-n-brand/10 text-n-slate-12 ring-2 ring-n-brand'
                : 'bg-n-solid-1 text-n-slate-11 ring-1 ring-n-weak'
            "
            @click="draft = { ...draft, site_action: action }"
          >
            {{ $t(`${KEY}.ACTIONS.${action}`) }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
