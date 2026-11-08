<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmGoogleConversionFeedAPI from 'dashboard/api/crmGoogleConversionFeed';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import FunilPassos from './FunilPassos.vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { TOKEN_MANAGE_PERMISSION } from 'dashboard/constants/permissions';

// #1384 — ligar o Google em três passos, um por vez: Copie → Cole → Ligue.
// O endereço é só desta conta; o Google passa a buscar as vendas nele. O
// rodapé da gaveta leva de um passo ao outro.
defineProps({
  passo: { type: Number, required: true },
});

defineEmits(['ir']);

const { t } = useI18n();
const link = ref('');
// O link é um token da plataforma: criar e ver fica com token_manage (#2027).
const canManageTokens = usePermissionGranted(TOKEN_MANAGE_PERMISSION);
onMounted(async () => {
  if (!canManageTokens.value) return;
  try {
    const { data } = await CrmGoogleConversionFeedAPI.create();
    link.value = data.url || '';
  } catch {
    link.value = '';
  }
});
const copiar = async () => {
  if (!link.value) return;
  try {
    await copyTextToClipboard(link.value);
    useAlert(t('CRM_KANBAN.GOOGLE_SYNC.COPIED'));
  } catch {
    useAlert(t('CRM_KANBAN.GOOGLE_SYNC.COPY_ERROR'));
  }
};

const google = defineModel('google', { type: Object, required: true });

const mudarNome = nome => {
  google.value = { ...google.value, conversionNames: { won: nome } };
};

const A = 'CRM_FUNIL.ANUNCIOS.GOOGLE';
const PASSOS = [`${A}.PASSO_1`, `${A}.PASSO_2`, `${A}.PASSO_3`];
</script>

<template>
  <div data-anuncio-google class="flex flex-col gap-6">
    <FunilPassos
      :atual="passo"
      :nomes="PASSOS"
      :rotulo="`${A}.PASSOS`"
      @ir="$emit('ir', $event)"
    />

    <section
      v-if="passo === 1"
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <div class="flex flex-col gap-1">
        <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ $t(`${A}.COPIE_TITULO`) }}
        </h3>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(`${A}.COPIE_TEXTO`) }}
        </p>
      </div>
      <p v-if="!canManageTokens" class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t(`${A}.SEM_TOKEN`) }}
      </p>
      <div v-else class="flex flex-wrap items-center gap-2">
        <input
          id="google-conversions-feed-url"
          :value="link"
          type="url"
          readonly
          :aria-label="$t(`${A}.COPIE_TITULO`)"
          class="reset-base !mb-0 min-w-0 flex-1 rounded-xl border border-n-weak bg-n-alpha-2 px-3 py-2.5 text-sm text-n-slate-11"
          :placeholder="$t('CRM_KANBAN.GOOGLE_SYNC.FEED_URL_PENDING')"
        />
        <Button
          :label="$t(`${A}.COPIAR`)"
          icon="i-lucide-copy"
          blue
          faded
          class="!min-h-11"
          :disabled="!link"
          @click="copiar"
        />
      </div>
    </section>

    <section
      v-else-if="passo === 2"
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${A}.COLE_TITULO`) }}
      </h3>
      <ol class="m-0 flex list-none flex-col gap-3 p-0">
        <li
          v-for="n in 3"
          :key="n"
          class="flex items-start gap-3 text-[0.9375rem] text-n-slate-12"
        >
          <span
            class="grid size-7 shrink-0 place-items-center rounded-full bg-n-amber-3 text-sm font-bold text-n-amber-11"
            aria-hidden="true"
          >
            {{ n }}
          </span>
          <span class="pt-0.5">{{ $t(`${A}.COLE_${n}`) }}</span>
        </li>
      </ol>
    </section>

    <section
      v-else
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <div class="flex flex-col gap-1">
        <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
          {{ $t(`${A}.LIGUE_TITULO`) }}
        </h3>
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(`${A}.LIGUE_TEXTO`) }}
        </p>
      </div>
      <Input
        :model-value="google.conversionNames.won"
        :label="$t(`${A}.NOME`)"
        :placeholder="$t(`${A}.NOME_EXEMPLO`)"
        custom-input-class="!h-11 !rounded-xl !bg-n-solid-1 !px-3"
        @update:model-value="mudarNome"
      />
    </section>
  </div>
</template>
