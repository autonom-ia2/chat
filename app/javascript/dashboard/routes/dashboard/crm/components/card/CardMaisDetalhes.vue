<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useOrigemLeiga } from './useOrigemLeiga';

// #1423 — "Mais detalhes", recolhido numa linha: de onde veio, o que já
// aconteceu, o resto do negócio (atenção, quando deve fechar, informações
// extras) e Arquivar. Cada linha abre a tela própria; nada aqui se repete nos
// cartões de cima.
const props = defineProps({
  card: { type: Object, required: true },
  conversao: { type: Object, default: null },
  formato: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
  arquivando: { type: Boolean, default: false },
});
defineEmits(['abrir', 'arquivar']);

const { t } = useI18n();
const leiga = useOrigemLeiga();
const R = 'CRM_CARD.RESUMO';

const origem = computed(() => leiga.daCampanha(props.card.campaigns));
const origemFrase = computed(() => {
  if (origem.value)
    return t(`${R}.ORIGEM_FRASE`, { origem: leiga.fonte(origem.value) });
  if (props.card.lead_form) return t(`${R}.ORIGEM_FORMULARIO`);
  if (props.conversao) return t(`${R}.AVISO_FACEBOOK`);
  return '';
});

const historico = computed(() => props.card.activities || []);
const historicoFrase = computed(() =>
  historico.value.length
    ? t(`${R}.HISTORICO_LINHA`, {
        total: t(
          `${R}.N_COISAS`,
          { n: historico.value.length },
          historico.value.length
        ),
        ha: props.formato.ha(historico.value[0].created_at),
      })
    : t(`${R}.SEM_HISTORICO`)
);

const extras = computed(
  () =>
    Object.values(props.card.custom_attributes || {}).filter(
      valor => valor !== null && valor !== ''
    ).length
);
const negocioFrase = computed(() =>
  [
    props.card.score ? t(`${R}.ATENCAO`, { nota: props.card.score }) : '',
    props.card.expected_close_at
      ? t(`${R}.FECHA_ATE`, {
          dia: props.formato.diaCurto(new Date(props.card.expected_close_at)),
        })
      : '',
    extras.value ? t(`${R}.EXTRAS`, { n: extras.value }, extras.value) : '',
  ]
    .filter(Boolean)
    .join(' · ')
);

const linhas = computed(() =>
  [
    origemFrase.value && {
      parte: 'origem',
      icone: 'i-lucide-megaphone',
      titulo: t(`${R}.ORIGEM`),
      frase: origemFrase.value,
    },
    {
      parte: 'historico',
      icone: 'i-lucide-history',
      titulo: t(`${R}.HISTORICO`),
      frase: historicoFrase.value,
    },
    negocioFrase.value && {
      parte: 'negocio',
      icone: 'i-lucide-list-plus',
      titulo: t(`${R}.MAIS_NEGOCIO`),
      frase: negocioFrase.value,
    },
  ].filter(Boolean)
);
</script>

<template>
  <details
    data-card-mais
    class="group rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <summary
      class="flex min-h-11 cursor-pointer list-none items-center gap-3 rounded-2xl px-4 py-2 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
    >
      <span class="text-sm font-semibold text-n-slate-12">
        {{ t(`${R}.MAIS_DETALHES`) }}
      </span>
      <span
        class="hidden min-w-0 flex-1 truncate text-sm text-n-slate-11 sm:block"
      >
        {{ t(`${R}.MAIS_DETALHES_DICA`) }}
      </span>
      <span class="flex-1 sm:hidden" aria-hidden="true" />
      <span
        class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-10 transition-transform group-open:rotate-180"
        aria-hidden="true"
      />
    </summary>
    <ul
      class="m-0 flex list-none flex-col divide-y divide-n-weak border-t border-n-weak p-0"
    >
      <li v-for="linha in linhas" :key="linha.parte">
        <button
          type="button"
          :data-mais="linha.parte"
          class="flex min-h-11 w-full items-start gap-3 px-4 py-3 text-start hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="$emit('abrir', linha.parte)"
        >
          <span
            class="mt-0.5 size-4 shrink-0 text-n-slate-11"
            :class="linha.icone"
            aria-hidden="true"
          />
          <span class="flex min-w-0 flex-1 flex-col">
            <span class="text-sm font-medium text-n-slate-11">
              {{ linha.titulo }}
            </span>
            <span class="text-[0.9375rem] text-n-slate-12">{{
              linha.frase
            }}</span>
          </span>
          <span
            class="i-lucide-chevron-right mt-0.5 size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </li>
      <li
        v-if="podeGerenciar"
        data-card-arquivar
        class="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
      >
        <p class="mb-0 min-w-0 flex-1 text-sm text-n-slate-11">
          {{ t('CRM_CARD.ARQUIVAR.DICA') }}
        </p>
        <Button
          :label="t('CRM_CARD.ARQUIVAR.BOTAO')"
          icon="i-lucide-archive"
          ruby
          ghost
          class="!min-h-11 shrink-0"
          :is-loading="arquivando"
          @click="$emit('arquivar')"
        />
      </li>
    </ul>
  </details>
</template>
