<script setup>
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';

// #1384 — um exemplo concreto do que os anúncios recebem quando alguém fecha:
// a Ana fecha a compra com R$ 1.200 e o aviso sai só com isto.
const props = defineProps({
  meta: { type: Object, required: true },
  google: { type: Object, required: true },
  resultado: { type: String, default: '' },
  // No passo a passo do Google, só ele aparece.
  soGoogle: { type: Boolean, default: false },
  // Etapa em que o Facebook e o Instagram também ficam sabendo.
  etapaAvisada: { type: String, default: '' },
  dinheiro: { type: Function, required: true },
});

const VALOR_DO_EXEMPLO = 1200;
const valor = computed(() => props.dinheiro(VALOR_DO_EXEMPLO));
const destinos = computed(() =>
  [
    props.meta.enabled && !props.soGoogle ? 'META' : '',
    props.google.enabled ? 'GOOGLE' : '',
  ].filter(Boolean)
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <span class="flex items-center gap-2">
        <span
          class="grid size-8 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xs font-bold text-n-blue-11"
          aria-hidden="true"
        >
          {{ $t('CRM_FUNIL.PREVIA.CLIENTE').slice(0, 2) }}
        </span>
        <span class="flex-1 text-sm font-semibold text-n-slate-12">{{
          $t('CRM_FUNIL.PREVIA.CLIENTE')
        }}</span>
        <span
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2.5 py-1 text-sm font-medium text-n-teal-11"
        >
          <span class="i-lucide-check size-4" aria-hidden="true" />
          {{ resultado }}
        </span>
      </span>
      <I18nT
        keypath="CRM_FUNIL.PREVIA.ANUNCIO_FECHOU"
        tag="p"
        scope="global"
        class="mb-0 text-[0.9375rem] text-n-slate-12"
      >
        <template #valor>
          <strong class="font-semibold text-n-teal-11">{{ valor }}</strong>
        </template>
      </I18nT>
    </section>
    <span
      class="i-lucide-arrow-down mx-auto size-5 text-n-slate-10"
      aria-hidden="true"
    />
    <section
      v-for="destino in destinos"
      :key="destino"
      class="flex flex-col gap-2 rounded-2xl border-2 border-n-blue-7 bg-n-solid-1 p-4"
    >
      <h4
        class="mb-1 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="size-4"
          :class="
            destino === 'META'
              ? 'i-ri-facebook-circle-fill text-n-blue-11'
              : 'i-lucide-search text-n-amber-11'
          "
          aria-hidden="true"
        />
        {{ $t(`CRM_FUNIL.PREVIA.RECEBE_${destino}`) }}
      </h4>
      <dl class="m-0 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
        <dt class="text-n-slate-11">{{ $t('CRM_FUNIL.PREVIA.O_QUE') }}</dt>
        <dd class="m-0 font-medium text-n-slate-12">
          {{ $t('CRM_FUNIL.ANUNCIOS.EVENTOS.WON') }}
        </dd>
        <dt class="text-n-slate-11">{{ $t('CRM_FUNIL.PREVIA.VALOR') }}</dt>
        <dd class="m-0 font-medium text-n-slate-12">{{ valor }}</dd>
        <template v-if="destino === 'META' && etapaAvisada">
          <dt class="text-n-slate-11">{{ $t('CRM_FUNIL.PREVIA.TAMBEM') }}</dt>
          <dd class="m-0 font-medium text-n-slate-12">
            {{ $t('CRM_FUNIL.PREVIA.CHEGOU_EM', { nome: etapaAvisada }) }}
          </dd>
        </template>
      </dl>
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          $t(
            destino === 'META'
              ? 'CRM_FUNIL.PREVIA.META_APRENDE'
              : 'CRM_FUNIL.PREVIA.GOOGLE_APRENDE'
          )
        }}
      </p>
    </section>
    <p
      v-if="!destinos.length"
      class="mb-0 rounded-2xl border border-dashed border-n-slate-6 p-4 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('CRM_FUNIL.PREVIA.ANUNCIO_DESLIGADO') }}
    </p>
  </div>
</template>
