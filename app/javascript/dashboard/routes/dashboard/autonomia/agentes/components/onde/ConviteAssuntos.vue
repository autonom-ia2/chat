<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgenteBotao from '../AgenteBotao.vue';

// #1366 (protótipo da Fase 2, rodada 2) — convite opcional, para quem conversa com clientes: os
// assuntos (funis) de que o agente cuida são escolhidos no CRM, em "Caixas no CRM › Quem cuida do
// quê?". "Fazer agora" abre o CRM em outra aba (a criação não se perde); "Depois" some com o convite.
defineProps({ nome: { type: String, required: true } });

const { t } = useI18n();
const router = useRouter();
const NS = 'AGENTS.JORNADA.ONDE.CONVITE';
const dispensado = ref(false);
const linkCaixas = computed(() => router.resolve({ name: 'crm_caixas' }).href);
</script>

<template>
  <div
    v-if="!dispensado"
    data-convite-assuntos
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 md:flex-row md:items-center"
  >
    <p class="flex items-start gap-3 m-0 text-sm grow text-n-slate-12">
      <span
        class="i-lucide-kanban-square size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.TEXTO`, { nome }) }}
    </p>
    <div class="flex flex-wrap items-center gap-2 shrink-0">
      <a
        data-fazer-agora
        :href="linkCaixas"
        target="_blank"
        rel="noopener noreferrer"
        class="relative inline-flex items-center justify-center gap-2 px-4 text-sm font-semibold text-white rounded-xl min-h-11 bg-n-blue-11 dark:text-n-slate-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      >
        {{ t(`${NS}.AGORA`) }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
      </a>
      <AgenteBotao data-depois variante="fantasma" @click="dispensado = true">
        {{ t(`${NS}.DEPOIS`) }}
      </AgenteBotao>
    </div>
  </div>
</template>
