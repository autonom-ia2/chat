<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1423 — o aviso ao Facebook e ao Instagram (MT-01), em palavras simples. A
// mesma linha de crm/meta_conversions que a CrmCardMetaConversion lê: enviado,
// enviando, não aceito (com o motivo do Facebook escondido em "Ver o motivo")
// ou não enviado por um motivo que a pessoa pode resolver.
const props = defineProps({
  conversao: { type: Object, default: null },
});
const { t } = useI18n();
const A = 'CRM_CARD.ORIGEM.AVISO_ESTADO';
const ESTADOS = {
  accepted: {
    tom: 'bg-n-teal-3 text-n-teal-11',
    icone: 'i-lucide-check',
    chave: 'ENVIADO',
  },
  pending: {
    tom: 'bg-n-amber-3 text-n-amber-11',
    icone: 'i-lucide-loader',
    chave: 'ENVIANDO',
  },
  error: {
    tom: 'bg-n-ruby-3 text-n-ruby-11',
    icone: 'i-lucide-circle-alert',
    chave: 'RECUSADO',
  },
  skipped: {
    tom: 'bg-n-alpha-2 text-n-slate-11',
    icone: 'i-lucide-circle-minus',
    chave: 'NAO_ENVIADO',
  },
};
// Só os motivos em que a pessoa pode fazer algo. Card que não veio de anúncio
// nem de página ('missing_ctwa_clid') fica quieto, como na gaveta antiga.
const MOTIVOS = {
  missing_pixel: 'SEM_PIXEL',
  event_too_old: 'VELHO',
  missing_credentials: 'SEM_ACESSO',
  no_meta_event: 'ETAPA_NAO_AVISA',
  missing_signals: 'SEM_SINAIS',
};
const QUANDO = { won: 'GANHO', lost: 'PERDIDO', moved: 'ETAPA' };

const estado = computed(() => {
  const { status, error_message: mensagem } = props.conversao || {};
  const base = ESTADOS[status];
  if (!base) return null;
  if (status === 'skipped') {
    const motivo = MOTIVOS[mensagem];
    return motivo ? { ...base, detalhe: t(`${A}.MOTIVO.${motivo}`) } : null;
  }
  if (status === 'error')
    return { ...base, detalhe: t(`${A}.RECUSADO_DICA`), bruto: mensagem || '' };
  return { ...base, detalhe: '' };
});
const quando = computed(() => {
  const chave = QUANDO[props.conversao?.event_type];
  return chave ? t(`${A}.QUANDO.${chave}`) : '';
});
</script>

<template>
  <div class="contents">
    <section
      v-if="estado"
      data-origem-aviso
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t('CRM_CARD.ORIGEM.AVISO') }}
      </h3>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_CARD.ORIGEM.AVISO_TEXTO') }}
      </p>
      <span
        class="inline-flex w-fit items-center gap-1.5 rounded-lg px-2 py-1 text-sm font-medium"
        :class="estado.tom"
      >
        <span class="size-4" :class="estado.icone" aria-hidden="true" />
        {{ t(`${A}.${estado.chave}`) }}
      </span>
      <p v-if="quando" class="mb-0 text-sm text-n-slate-11">{{ quando }}</p>
      <p v-if="estado.detalhe" class="mb-0 text-sm text-n-slate-12">
        {{ estado.detalhe }}
      </p>
      <details v-if="estado.bruto" class="group text-sm text-n-slate-11">
        <summary
          class="flex min-h-11 w-fit cursor-pointer list-none items-center gap-1 rounded-lg font-medium text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
        >
          {{ t(`${A}.VER_MOTIVO`) }}
          <span
            class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </summary>
        <span class="block break-words">{{ estado.bruto }}</span>
      </details>
    </section>
  </div>
</template>
