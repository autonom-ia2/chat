<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';

// #1181 (herói T01) — a conta ainda não tem canal: dá para montar e testar o agente agora e conectar depois. Quem pode
// conectar canal recebe o link (nova aba); quem não pode, o "peça a um administrador". #3219: sai do herói da lista
// e fica no passo 2 de atender clientes, o único papel que precisa de canal.
const { t } = useI18n();
const router = useRouter();
const { podeConectarCanal } = usePermissoesDaJornada();
const linkConectarCanal = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);
</script>

<template>
  <div
    data-sem-canal
    class="flex flex-col gap-2 p-4 text-sm rounded-2xl bg-n-amber-2 text-n-slate-12"
  >
    <p class="m-0">{{ t('AGENTS.JORNADA.HEROI.SEM_CANAL') }}</p>
    <a
      v-if="podeConectarCanal"
      :href="linkConectarCanal"
      target="_blank"
      rel="noopener noreferrer"
      class="relative inline-flex items-center gap-1 font-semibold underline min-h-11 w-fit text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
    >
      {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
      <span class="i-lucide-external-link size-4" aria-hidden="true" />
      <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
    </a>
    <p v-else class="m-0 text-n-slate-11">
      {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
    </p>
  </div>
</template>
