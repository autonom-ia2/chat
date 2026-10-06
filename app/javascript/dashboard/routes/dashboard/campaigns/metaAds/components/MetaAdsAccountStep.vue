<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { errorMessageKey, money, relativeTime } from '../metaAdsHelpers';

// Anúncios da Meta (#1047), passo 2: a conta de anúncios em lista, sem digitar ID. A conta com
// mais gasto e o código do site (Pixel) usado mais recentemente vêm escolhidos; o código do site
// fica numa linha com "Alterar", para a tela ter uma decisão só. "Conectada" só depois que o
// servidor lê a conta (CA-1.2). Conta compartilhada que a Meta ainda não liberou: a escolha libera
// e lê; os códigos do site aparecem em seguida.
const props = defineProps({
  mode: { type: String, required: true },
  partnerName: { type: String, default: 'Hub2You' },
  current: { type: Object, default: null },
});

const emit = defineEmits(['saved', 'back']);

const { t, locale } = useI18n();

const accounts = ref([]);
const loading = ref(false);
const loadError = ref('');
const chosenId = ref(null);
const pixels = ref(null);
const loadingPixels = ref(false);
const pixelId = ref('');
const pickingPixel = ref(false);
const saving = ref(false);
// Erro da gravação fica na tela, embaixo do botão: o balão sumia antes de a pessoa ler (#1068).
const saveError = ref('');

const chosen = computed(() =>
  accounts.value.find(account => account.id === chosenId.value)
);
const chosenPixel = computed(() =>
  (pixels.value || []).find(pixel => pixel.id === pixelId.value)
);
const pixelOptions = computed(() => [
  ...(pixels.value || []),
  { id: '', name: null },
]);

const errorText = error =>
  t(errorMessageKey(error), { partner: props.partnerName });

const latestPixel = list =>
  [...list].sort((a, b) =>
    String(b.last_fired_time || '').localeCompare(
      String(a.last_fired_time || '')
    )
  )[0];

const loadPixels = async () => {
  pixels.value = null;
  pickingPixel.value = false;
  if (!chosen.value?.ready) return;

  loadingPixels.value = true;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.pixels(
      props.mode,
      chosen.value.id
    );
    pixels.value = data.pixels || [];
    const keep = pixels.value.find(
      pixel => pixel.id === props.current?.pixel?.id
    );
    pixelId.value = keep?.id || latestPixel(pixels.value)?.id || '';
  } catch (error) {
    pixels.value = [];
    saveError.value = errorText(error);
  } finally {
    loadingPixels.value = false;
  }
};

const choose = async id => {
  if (chosenId.value === id && pixels.value) return;
  chosenId.value = id;
  await loadPixels();
};

const load = async () => {
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmMetaAdsConnectionAPI.adAccounts(props.mode);
    accounts.value = data.ad_accounts || [];
    const preset =
      accounts.value.find(item => item.id === props.current?.ad_account?.id) ||
      accounts.value.find(item => item.recommended) ||
      accounts.value[0];
    if (preset) await choose(preset.id);
  } catch (error) {
    loadError.value = errorText(error);
  } finally {
    loading.value = false;
  }
};

// Sem códigos do site ainda lidos (conta recém-liberada), a primeira gravação libera e lê a conta;
// depois a pessoa confere o código do site e grava de novo.
const save = async () => {
  if (!chosen.value) return;

  saving.value = true;
  saveError.value = '';
  const firstRelease = !chosen.value.ready;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.select({
      mode: props.mode,
      adAccountId: chosen.value.id,
      pixelId: firstRelease ? null : pixelId.value || null,
    });
    if (firstRelease) {
      accounts.value = accounts.value.map(item =>
        item.id === chosen.value.id ? { ...item, ready: true } : item
      );
      await loadPixels();
      if (pixels.value?.length) return;
    }
    useAlert(t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.SAVED'));
    emit('saved', data);
  } catch (error) {
    saveError.value = errorText(error);
  } finally {
    saving.value = false;
  }
};

const accountDetail = account => {
  if (!account.ready) return t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.WAITING');
  if (!account.active) return t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.INACTIVE');
  if (account.spend_30d === null || account.spend_30d === undefined) {
    return '';
  }
  return t(
    account.spend_30d > 0
      ? 'CRM_KANBAN.META_ADS_HUB.ACCOUNT.SPEND'
      : 'CRM_KANBAN.META_ADS_HUB.ACCOUNT.NO_SPEND',
    { value: money(account.spend_30d, account.currency, locale.value) }
  );
};

const pixelSignal = pixel => {
  const time = relativeTime(pixel.last_fired_time, locale.value);
  return time
    ? t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_LAST', { time })
    : t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NEVER');
};

onMounted(load);
</script>

<template>
  <section data-meta-ads-account class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <h3 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
        {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.TITLE') }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.HINT') }}
      </p>
    </header>

    <!-- Por qual caminho a conta está sendo lida: nada de trocar de modo em silêncio (#1068). -->
    <div
      data-account-mode
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 rounded-xl bg-n-alpha-1"
    >
      <span class="flex items-center gap-2 text-sm text-n-slate-12">
        <span
          class="size-4 text-n-blue-11"
          :class="
            mode === 'partner' ? 'i-lucide-handshake' : 'i-lucide-key-round'
          "
          aria-hidden="true"
        />
        {{
          mode === 'partner'
            ? $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.VIA_PARTNER', {
                partner: partnerName,
              })
            : $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.VIA_TOKEN')
        }}
      </span>
      <button
        type="button"
        data-account-switch
        class="inline-flex items-center px-2 text-sm font-semibold bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="emit('back')"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.SWITCH') }}
      </button>
    </div>

    <div
      v-if="loading"
      class="flex items-center gap-3 p-5 text-sm rounded-2xl bg-n-alpha-1 text-n-slate-11"
    >
      <Spinner class="size-4" />
      {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.LOADING') }}
    </div>

    <div
      v-else-if="loadError || !accounts.length"
      data-account-empty
      class="flex flex-col items-start gap-3 p-5 rounded-2xl bg-n-amber-2"
    >
      <p class="m-0 text-sm text-n-amber-11">
        {{ loadError || $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.EMPTY') }}
      </p>
      <div class="flex gap-2">
        <Button
          class="!min-h-11 !rounded-xl"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="$t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.RETRY')"
          @click="load"
        />
        <Button
          class="!min-h-11 !rounded-xl"
          size="sm"
          variant="ghost"
          color="slate"
          :label="$t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.BACK')"
          @click="emit('back')"
        />
      </div>
    </div>

    <template v-else>
      <!-- Rádios nativos (escondidos): setas do teclado e leitor de tela funcionam sem código extra. -->
      <fieldset class="flex flex-col gap-2 p-0 m-0 border-0">
        <legend class="sr-only">
          {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.TITLE') }}
        </legend>
        <label
          v-for="account in accounts"
          :key="account.id"
          :data-ad-account="account.id"
          class="flex items-center w-full gap-3 px-4 py-3 border cursor-pointer min-h-[4.5rem] rounded-xl has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
          :class="
            account.id === chosenId
              ? 'border-n-blue-8 bg-n-blue-2'
              : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
          "
        >
          <input
            type="radio"
            name="meta-ad-account"
            class="sr-only"
            :value="account.id"
            :checked="account.id === chosenId"
            @change="choose(account.id)"
          />
          <span
            class="flex-none rounded-full size-5"
            :class="
              account.id === chosenId
                ? 'border-[6px] border-n-blue-9'
                : 'border-2 border-n-slate-7'
            "
            aria-hidden="true"
          />
          <span class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-semibold text-n-slate-12">
                {{ account.name }}
              </span>
              <span
                v-if="account.recommended"
                class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.RECOMMENDED') }}
              </span>
            </span>
            <span class="text-xs text-n-slate-11">
              {{ accountDetail(account) }}
            </span>
          </span>
        </label>
      </fieldset>

      <div
        v-if="chosen?.ready"
        data-pixels
        class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
      >
        <div
          v-if="loadingPixels"
          class="flex items-center gap-2 text-sm text-n-slate-11"
        >
          <Spinner class="size-4" />
          {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_LOADING') }}
        </div>

        <div
          v-else-if="!pickingPixel"
          data-pixel-summary
          class="flex flex-wrap items-center justify-between gap-2"
        >
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-medium text-n-slate-12">
              {{
                chosenPixel
                  ? $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_SUMMARY', {
                      pixel: chosenPixel.name,
                    })
                  : $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_SUMMARY_NONE')
              }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_HINT') }}
            </span>
          </span>
          <button
            type="button"
            data-pixel-change
            class="inline-flex items-center px-3 text-sm font-semibold underline bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="pickingPixel = true"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_CHANGE') }}
          </button>
        </div>

        <fieldset v-else class="flex flex-col gap-2 p-0 m-0 border-0">
          <legend class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_TITLE') }}
          </legend>
          <div class="grid gap-2 sm:grid-cols-2">
            <label
              v-for="pixel in pixelOptions"
              :key="pixel.id || 'none'"
              :data-pixel="pixel.id || 'none'"
              class="flex items-start gap-3 p-3 border cursor-pointer rounded-xl min-h-11 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
              :class="
                pixelId === pixel.id
                  ? 'border-n-blue-7 bg-n-blue-2'
                  : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
              "
            >
              <input
                v-model="pixelId"
                type="radio"
                name="meta-pixel"
                class="sr-only"
                :value="pixel.id"
              />
              <span
                class="flex-none mt-0.5 rounded-full size-4"
                :class="
                  pixelId === pixel.id
                    ? 'border-[5px] border-n-blue-9'
                    : 'border-2 border-n-slate-7'
                "
                aria-hidden="true"
              />
              <span class="flex flex-col min-w-0">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{
                    pixel.name ||
                    $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NONE')
                  }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    pixel.id
                      ? pixelSignal(pixel)
                      : $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NONE_HINT')
                  }}
                </span>
              </span>
            </label>
          </div>
        </fieldset>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <Button
          class="!min-h-11 !rounded-xl"
          data-use-account
          icon="i-lucide-check"
          :is-loading="saving"
          :disabled="!chosen || saving || loadingPixels"
          :label="
            saving
              ? $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.USING')
              : $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.USE')
          "
          @click="save"
        />
        <Button
          class="!min-h-11 !rounded-xl"
          variant="ghost"
          color="slate"
          :label="$t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.BACK')"
          @click="emit('back')"
        />
      </div>
      <p
        v-if="saveError"
        data-account-error
        role="alert"
        class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        <span
          class="flex-none mt-0.5 i-lucide-circle-alert size-4"
          aria-hidden="true"
        />
        {{ saveError }}
      </p>
    </template>
  </section>
</template>
