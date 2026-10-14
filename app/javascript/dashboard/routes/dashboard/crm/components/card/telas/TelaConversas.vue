<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #1423 — as conversas do card (CV-01): "Em resumo" no topo (IA-02) e, para
// cada uma, número, caixa, situação, última conversa e quem atende, com
// "Abrir conversa". O servidor manda até 10, só as que a pessoa pode ver.
defineProps({
  conversas: { type: Array, required: true },
  formato: { type: Object, required: true },
  carregando: { type: Boolean, default: false },
  resumo: { type: Object, required: true },
  ia: { type: Boolean, default: false },
  podeIa: { type: Boolean, default: false },
});
defineEmits(['abrir', 'atualizar']);

const { t } = useI18n();
const C = 'CRM_CARD.CONVERSAS';
const SITUACAO = {
  open: 'OPEN',
  pending: 'PENDING',
  resolved: 'RESOLVED',
  snoozed: 'SNOOZED',
};
const situacao = status =>
  t(
    `CRM_KANBAN.DRAWER.CONVERSATION_STATUS_${SITUACAO[String(status || '').toLowerCase()] || 'UNKNOWN'}`
  );
</script>

<template>
  <section class="flex flex-col gap-4" data-tela="conversas">
    <section
      v-if="ia && resumo.temConversa"
      data-conversas-resumo
      class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3
          class="mb-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-sparkles size-4 text-n-iris-11"
            aria-hidden="true"
          />
          {{ t('CRM_CARD.LADO.EM_RESUMO') }}
        </h3>
        <Button
          v-if="podeIa"
          :label="t(`${C}.ATUALIZAR`)"
          icon="i-lucide-refresh-cw"
          slate
          faded
          class="!min-h-11"
          :is-loading="resumo.carregando"
          @click="$emit('atualizar')"
        />
      </div>
      <p
        v-if="resumo.carregando"
        role="status"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t(`${C}.LENDO`) }}
      </p>
      <p
        v-else-if="resumo.texto"
        class="mb-0 whitespace-pre-line text-[0.9375rem] leading-relaxed text-n-slate-12"
      >
        {{ resumo.texto }}
      </p>
      <p v-else-if="resumo.erro" class="mb-0 text-sm text-n-ruby-11">
        {{ t(`${C}.RESUMO_ERRO`) }}
      </p>
      <p v-else class="mb-0 text-sm text-n-slate-11">
        {{ t(`${C}.SEM_RESUMO`) }}
      </p>
      <p
        v-if="resumo.texto && resumo.quando"
        class="mb-0 text-xs text-n-slate-11"
      >
        {{
          t('CRM_CARD.LADO.ATUALIZADO', { quando: formato.ha(resumo.quando) })
        }}
      </p>
    </section>

    <ul v-if="conversas.length" class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="conversa in conversas"
        :key="conversa.id || conversa.display_id"
        data-conversa
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:flex-row sm:items-center sm:p-5"
      >
        <span
          class="grid size-10 shrink-0 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-message-circle size-5" />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-0.5">
          <p class="mb-0 text-base font-semibold text-n-slate-12">
            {{
              t(`${C}.ITEM`, {
                numero: conversa.display_id,
                caixa:
                  conversa.inbox_name ||
                  conversa.inbox?.name ||
                  t('CRM_KANBAN.DRAWER.NO_INBOX'),
              })
            }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{
              [
                situacao(conversa.status),
                conversa.last_activity_at
                  ? t(`${C}.ULTIMA`, {
                      quando: formato.ha(conversa.last_activity_at),
                    })
                  : '',
                conversa.assignee_name
                  ? t(`${C}.ATENDE`, { nome: conversa.assignee_name })
                  : t(`${C}.SEM_ATENDENTE`),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </p>
        </div>
        <Button
          :label="t('CRM_CARD.ABRIR_CONVERSA')"
          icon="i-lucide-external-link"
          slate
          outline
          class="!min-h-11 shrink-0 !outline-n-weak"
          @click="$emit('abrir', conversa.display_id)"
        />
      </li>
    </ul>
    <p v-if="conversas.length" class="mb-0 text-sm text-n-slate-11">
      {{ t(`${C}.SO_AS_SUAS`) }}
    </p>
    <div
      v-else-if="!carregando"
      class="rounded-2xl border border-dashed border-n-weak px-4 py-10 text-center"
    >
      <p class="mb-0 text-base text-n-slate-12">{{ t(`${C}.VAZIO`) }}</p>
    </div>
  </section>
</template>
