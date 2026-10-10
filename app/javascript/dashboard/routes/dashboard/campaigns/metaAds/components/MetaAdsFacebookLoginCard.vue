<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMetaAdsFacebookLogin } from '../useMetaAdsFacebookLogin';
import { errorMessageKey } from '../metaAdsHelpers';

// Anúncios da Meta, passo 1 com "Entrar com o Facebook" (#1069). Uma ação só, o botão do Facebook.
// Antes dele, o que vai acontecer na janela da Meta, com o pedido que mais importa: deixar tudo
// marcado e tocar em Continuar até o fim. É isso que garante o acesso aos anúncios. Os outros jeitos
// de conectar ficam escondidos atrás de um link.
const props = defineProps({
  config: { type: Object, required: true },
  partnerName: { type: String, default: 'Hub2You' },
  canShare: { type: Boolean, default: false },
});

const emit = defineEmits(['connected', 'partner', 'token']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CONNECT.FACEBOOK';
const HOW = [1, 2, 3];
const TRUST = ['TRUST_PASSWORD', 'TRUST_ADS', 'TRUST_OFF'];
const POPUP_STEPS = ['POPUP_STEP_1', 'POPUP_STEP_2', 'POPUP_STEP_3'];
// Recusas com título próprio; as outras mostram só a frase do erro.
const ERROR_TITLES = {
  no_ad_account: 'NO_AD_ACCOUNT_TITLE',
  missing_ads_read: 'NO_ACCESS_TITLE',
};

const { t } = useI18n();
const { isConnecting, preload, connect } = useMetaAdsFacebookLogin();
const otherOpen = ref(false);
// null, { popup: true } ou { title, text, tone } — o aviso do último clique.
const notice = ref(null);

const errorNotice = error => {
  const code = error?.response?.data?.error;
  const text = t(errorMessageKey(error), { partner: props.partnerName });
  const titleKey = ERROR_TITLES[code];
  return {
    tone: code === 'meta_unavailable' ? 'ruby' : 'amber',
    title: titleKey ? t(`${KEY}.${titleKey}`) : '',
    text,
  };
};

const signIn = async () => {
  notice.value = null;
  try {
    const data = await connect(props.config);
    // Sem código de volta: a pessoa fechou a janela ou o navegador barrou o popup. As duas coisas chegam
    // iguais do Facebook, então a tela explica como liberar em vez de não dizer nada.
    if (data) emit('connected', data);
    else notice.value = { popup: true };
  } catch (error) {
    notice.value = errorNotice(error);
  }
};

const ctaLabel = computed(() =>
  notice.value ? t(`${KEY}.RETRY`) : t(`${KEY}.CTA`)
);

onMounted(() => {
  // O SDK carregado antes deixa o clique abrir o popup dentro do gesto da pessoa. Falha aparece no clique.
  preload(props.config).catch(() => {});
});
</script>

<template>
  <section data-connect-facebook class="flex flex-col gap-5">
    <header class="flex flex-col gap-2">
      <h3
        class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12 text-balance"
      >
        {{ $t(`${KEY}.TITLE`) }}
      </h3>
      <p class="max-w-2xl m-0 text-base text-n-slate-11">
        {{ $t(`${KEY}.LEAD`) }}
      </p>
    </header>

    <ol
      class="grid gap-3 p-0 m-0 list-none sm:grid-cols-3"
      :aria-label="$t(`${KEY}.HOW_LABEL`)"
    >
      <li
        v-for="item in HOW"
        :key="item"
        :data-facebook-how="item"
        class="flex flex-col gap-2 p-4 border rounded-2xl"
        :class="
          item === 2
            ? 'border-n-blue-8 bg-n-blue-2'
            : 'border-n-weak bg-n-alpha-1'
        "
      >
        <span
          class="grid text-sm font-bold rounded-full size-7 place-items-center bg-n-blue-3 text-n-blue-11"
        >
          {{ item }}
        </span>
        <span
          class="text-base font-semibold"
          :class="item === 2 ? 'text-n-blue-11' : 'text-n-slate-12'"
        >
          {{ $t(`${KEY}.HOW_${item}_TITLE`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ $t(`${KEY}.HOW_${item}_TEXT`) }}
        </span>
      </li>
    </ol>

    <div class="flex flex-col gap-3">
      <button
        type="button"
        data-facebook-login
        :disabled="isConnecting"
        class="inline-flex items-center self-start justify-center gap-3 px-7 text-base font-semibold text-white border-0 rounded-2xl min-h-14 bg-[#1460D1] hover:bg-[#0F52B8] disabled:cursor-wait focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        @click="signIn"
      >
        <span
          class="i-ri-facebook-circle-fill size-6"
          :class="{ 'animate-pulse': isConnecting }"
          aria-hidden="true"
        />
        {{ ctaLabel }}
      </button>

      <p
        v-if="isConnecting"
        data-facebook-waiting
        role="status"
        class="max-w-2xl px-4 py-3 m-0 text-sm font-medium rounded-xl bg-n-blue-2 text-n-blue-11"
      >
        {{ $t(`${KEY}.WAITING`) }}
      </p>

      <div
        v-if="notice?.popup"
        data-facebook-hint
        role="alert"
        class="flex flex-col max-w-2xl gap-1 px-4 py-3 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        <strong>{{ $t(`${KEY}.POPUP_TITLE`) }}</strong>
        <span>{{ $t(`${KEY}.POPUP_TEXT`) }}</span>
        <ol class="m-0 ps-5">
          <li v-for="step in POPUP_STEPS" :key="step">
            {{ $t(`${KEY}.${step}`) }}
          </li>
        </ol>
      </div>
      <div
        v-else-if="notice"
        data-facebook-error
        role="alert"
        class="flex flex-col max-w-2xl gap-1 px-4 py-3 text-sm rounded-xl"
        :class="
          notice.tone === 'ruby'
            ? 'bg-n-ruby-2 text-n-ruby-11'
            : 'bg-n-amber-2 text-n-amber-11'
        "
      >
        <strong v-if="notice.title">{{ notice.title }}</strong>
        <span>{{ notice.text }}</span>
      </div>

      <ul
        class="flex flex-wrap p-0 m-0 list-none gap-x-5 gap-y-1 text-sm text-n-slate-11"
      >
        <li
          v-for="item in TRUST"
          :key="item"
          class="inline-flex items-center gap-1.5"
        >
          <span
            class="i-lucide-check size-4 text-n-teal-11"
            aria-hidden="true"
          />
          {{ $t(`${KEY}.${item}`) }}
        </li>
      </ul>
    </div>

    <!-- Com a janela do Facebook aberta, os outros jeitos somem: trocar de caminho desmontaria o cartão
         e a conexão gravada pelo servidor não chegaria à página. -->
    <div
      v-if="!isConnecting"
      class="flex flex-col gap-3 pt-4 border-t border-n-weak"
    >
      <button
        type="button"
        data-facebook-other
        aria-controls="meta-ads-facebook-other"
        :aria-expanded="otherOpen"
        class="inline-flex items-center self-start px-0 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 underline-offset-2 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="otherOpen = !otherOpen"
      >
        {{ $t(`${KEY}.OTHER_WAYS`) }}
      </button>
      <div
        v-if="otherOpen"
        id="meta-ads-facebook-other"
        class="grid gap-3 sm:grid-cols-2"
      >
        <article
          v-if="canShare"
          data-facebook-other-partner
          class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
        >
          <span class="text-sm font-semibold text-n-slate-12">
            {{ $t(`${KEY}.PARTNER_TITLE`, { partner: partnerName }) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`${KEY}.PARTNER_TEXT`, { partner: partnerName }) }}
          </span>
          <button
            type="button"
            class="self-start px-4 text-sm font-semibold border rounded-xl min-h-11 border-n-weak bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="emit('partner')"
          >
            {{ $t(`${KEY}.PARTNER_CTA`) }}
          </button>
        </article>
        <article
          data-facebook-other-token
          class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
        >
          <span class="text-sm font-semibold text-n-slate-12">
            {{ $t(`${KEY}.TOKEN_TITLE`) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`${KEY}.TOKEN_TEXT`) }}
          </span>
          <button
            type="button"
            data-connect-token-link
            class="self-start px-4 text-sm font-semibold border rounded-xl min-h-11 border-n-weak bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="emit('token')"
          >
            {{ $t(`${KEY}.TOKEN_CTA`) }}
          </button>
        </article>
      </div>
    </div>
  </section>
</template>
