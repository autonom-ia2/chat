<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import MetaAdsConnectDialog from 'dashboard/components-next/Campaigns/TrackedLinks/MetaAdsConnectDialog.vue';
import MetaAdsFacebookLoginCard from './MetaAdsFacebookLoginCard.vue';

// Anúncios da Meta (#1047), passo 1. Uma ação: compartilhar a conta com a plataforma, sem chave.
// A chave de acesso fica como link discreto — e vira o caminho único quando compartilhar não dá
// (plataforma não configurada, ou a conta sem um WhatsApp ligado pela Meta, que prova de quem é a
// conta de anúncios).
// "Entrar com o Facebook" (#1069), quando configurado, ocupa o passo inteiro (MetaAdsFacebookLoginCard):
// compartilhar e a chave ficam em "Prefere outro jeito de conectar?".
const props = defineProps({
  connection: { type: Object, required: true },
});

const emit = defineEmits(['partner', 'token', 'facebookLogin']);

// Tela de Parceiros do Gerenciador de Negócios: a pessoa cola o código e marca os ativos. Sem o
// portfólio no endereço a Meta abre "conteúdo não disponível" (#1068); o do WhatsApp da conta é o certo.
const META_PARTNERS_URL =
  'https://business.facebook.com/latest/settings/partners';
const STEPS = ['PARTNER_STEP_1', 'PARTNER_STEP_2', 'PARTNER_STEP_3'];

const { t } = useI18n();
const tokenDialog = ref(null);

const partner = computed(() => props.connection.partner || {});
const partnerName = computed(() => partner.value.business_name || 'Hub2You');
const canShare = computed(
  () => partner.value.available && props.connection.whatsapp_portfolio
);
const partnersUrl = computed(() => {
  const portfolio = props.connection.client_portfolio_id;
  return portfolio
    ? `${META_PARTNERS_URL}?business_id=${encodeURIComponent(portfolio)}`
    : META_PARTNERS_URL;
});
const facebook = computed(() => props.connection.facebook_login || {});
const facebookAvailable = computed(() => Boolean(facebook.value.available));
// Com o Facebook disponível, o compartilhamento só abre quando a pessoa pede.
const partnerOpen = ref(false);
const showFacebook = computed(
  () => facebookAvailable.value && !partnerOpen.value
);
const showPartner = computed(
  () => canShare.value && (!facebookAvailable.value || partnerOpen.value)
);
const root = ref(null);
// Trocar entre o Facebook e o compartilhamento troca o conteúdo inteiro do passo: o foco vai para o primeiro
// controle do que apareceu, para quem usa teclado ou leitor de tela não cair no topo da página.
const switchTo = async (sharing, selector) => {
  partnerOpen.value = sharing;
  await nextTick();
  root.value?.querySelector(selector)?.focus();
};

const shareBlockedHint = computed(() =>
  partner.value.available
    ? t('CRM_KANBAN.META_ADS_HUB.CONNECT.NO_PORTFOLIO')
    : t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_UNAVAILABLE')
);

const copyId = async () => {
  try {
    await navigator.clipboard.writeText(partner.value.business_id || '');
    useAlert(t('CRM_KANBAN.META_ADS_HUB.CONNECT.COPIED'));
  } catch {
    // Sem permissão de área de transferência: o código segue visível para copiar à mão.
  }
};
</script>

<template>
  <section ref="root" data-meta-ads-connect class="flex flex-col gap-4">
    <MetaAdsFacebookLoginCard
      v-if="showFacebook"
      :config="facebook"
      :partner-name="partnerName"
      :can-share="canShare"
      @connected="emit('facebookLogin', $event)"
      @partner="switchTo(true, '[data-facebook-back]')"
      @token="tokenDialog?.open()"
    />
    <template v-else>
      <button
        v-if="facebookAvailable"
        type="button"
        data-facebook-back
        class="inline-flex items-center self-start gap-1 px-0 text-sm font-semibold bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="switchTo(false, '[data-facebook-login]')"
      >
        <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.FACEBOOK.BACK') }}
      </button>
      <h3
        v-else
        class="m-0 text-xl font-semibold tracking-tight text-n-slate-12"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.TITLE') }}
      </h3>
    </template>

    <article
      v-if="showPartner"
      data-connect-partner
      class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <header class="flex flex-wrap items-center gap-2">
        <span
          class="i-lucide-handshake size-5 text-n-blue-11"
          aria-hidden="true"
        />
        <h4 class="m-0 text-base font-semibold text-n-slate-12">
          {{
            $t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_TITLE', {
              partner: partnerName,
            })
          }}
        </h4>
        <span
          v-if="!facebookAvailable"
          class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-blue-3 text-n-blue-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_BADGE') }}
        </span>
      </header>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          $t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_HINT', {
            partner: partnerName,
          })
        }}
      </p>

      <div class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1">
        <div class="flex flex-wrap items-center gap-3">
          <span class="text-xs text-n-slate-11">
            {{
              $t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_ID_LABEL', {
                partner: partnerName,
              })
            }}
          </span>
          <code
            data-partner-id
            class="px-3 py-1.5 font-mono text-base rounded-lg select-all bg-n-solid-1 text-n-slate-12"
          >
            {{ partner.business_id }}
          </code>
          <Button
            class="!min-h-11 !rounded-xl"
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-copy"
            :label="$t('CRM_KANBAN.META_ADS_HUB.CONNECT.COPY')"
            @click="copyId"
          />
          <a
            data-open-meta
            :href="partnersUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1.5 px-3 text-sm font-semibold rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-2"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.OPEN_META') }}
            <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
          </a>
        </div>
        <span class="text-sm font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_STEPS_TITLE') }}
        </span>
        <ol class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="(step, index) in STEPS"
            :key="step"
            class="flex gap-3 text-sm text-n-slate-12"
          >
            <span
              class="grid flex-none text-xs font-bold rounded-full size-6 place-items-center bg-n-slate-3 text-n-slate-11"
            >
              {{ index + 1 }}
            </span>
            {{
              $t(`CRM_KANBAN.META_ADS_HUB.CONNECT.${step}`, {
                partner: partnerName,
              })
            }}
          </li>
        </ol>
        <details class="text-xs text-n-slate-11">
          <summary class="cursor-pointer select-none text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.DETAILS') }}
          </summary>
          <p class="mt-2 mb-0">
            {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.DETAILS_TEXT') }}
          </p>
        </details>
      </div>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <Button
          class="!min-h-11 !rounded-xl"
          data-partner-done
          icon="i-lucide-check"
          :label="$t('CRM_KANBAN.META_ADS_HUB.CONNECT.PARTNER_DONE')"
          @click="emit('partner')"
        />
        <button
          v-if="!facebookAvailable"
          type="button"
          data-connect-token-link
          class="inline-flex items-center px-2 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 underline-offset-2 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="tokenDialog?.open()"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.TOKEN_LINK') }}
        </button>
      </div>
    </article>

    <template v-if="!canShare && !facebookAvailable">
      <p
        data-connect-share-blocked
        class="p-4 m-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        {{ shareBlockedHint }}
      </p>
      <article
        data-connect-token
        class="flex flex-wrap items-center justify-between gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <h4 class="m-0 text-base font-semibold text-n-slate-12">
            {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.TOKEN_TITLE') }}
          </h4>
          <p class="m-0 text-sm text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.CONNECT.TOKEN_HINT') }}
          </p>
        </div>
        <Button
          class="!min-h-11 !rounded-xl"
          icon="i-lucide-key-round"
          :label="$t('CRM_KANBAN.META_ADS_HUB.CONNECT.TOKEN_CTA')"
          @click="tokenDialog?.open()"
        />
      </article>
    </template>

    <MetaAdsConnectDialog ref="tokenDialog" @connected="emit('token')" />
  </section>
</template>
