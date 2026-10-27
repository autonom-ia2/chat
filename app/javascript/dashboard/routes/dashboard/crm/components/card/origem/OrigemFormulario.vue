<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { phoneLabel } from 'dashboard/routes/dashboard/campaigns/metaAds/semLogin/anunciosSemLogin';

// #1423 — o que o cliente preencheu na página (VC-05), como chegou: os mesmos
// campos da CrmCardLeadForm, sem o título técnico.
const props = defineProps({
  formulario: { type: Object, default: null },
});
const { t, locale } = useI18n();
const campos = computed(() =>
  (props.formulario?.fields || []).filter(
    campo => campo && String(campo.value ?? '').trim()
  )
);
// Telefone do formulário do anúncio da Meta (#2195) chega cru ("+5511987651201"): o mesmo formato da lista de
// quem chegou pelos formulários ("(11) 98765-1201" no Brasil).
const valorDe = campo =>
  campo.key === 'phone_number' ? phoneLabel(campo.value) : campo.value;
const quando = computed(() =>
  relativeTimeFromISO(props.formulario?.captured_at, locale.value)
);
</script>

<template>
  <div class="contents">
    <div
      v-if="campos.length"
      class="flex flex-col gap-2"
      data-origem-formulario
    >
      <p v-if="quando" class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_CARD.ORIGEM.PREENCHEU_QUANDO', { quando }) }}
      </p>
      <dl class="m-0 flex flex-col divide-y divide-n-weak">
        <div
          v-for="(campo, indice) in campos"
          :key="`${campo.key}-${indice}`"
          class="grid grid-cols-1 gap-0.5 py-2.5 sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] sm:gap-3"
        >
          <dt class="break-words text-sm text-n-slate-11">
            {{ campo.label || campo.key }}
          </dt>
          <dd class="m-0 break-words text-[0.9375rem] text-n-slate-12">
            {{ valorDe(campo) }}
          </dd>
        </div>
      </dl>
    </div>
  </div>
</template>
