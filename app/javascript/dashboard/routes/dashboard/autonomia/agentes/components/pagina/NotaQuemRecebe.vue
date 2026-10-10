<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';

// #1181 (DECISOES.md item 8) — a nota "Quando não souber, {nome} passa a conversa para a equipe.
// Quem recebe é definido em Atribuição." com o link "Escolher quem recebe" só para quem pode abrir
// a tela de Atribuição. Sem CRM e IA do CRM ligados na instalação a tela não existe: aí não faz
// sentido mandar pedir a um administrador, e a linha some.
defineProps({
  nome: { type: String, required: true },
});

const { t } = useI18n();
const router = useRouter();
const { podeEscolherQuemRecebe, crmLigado } = usePermissoesDaJornada();
const NS = 'AGENTS.JORNADA.ONDE_QUANDO';

const linkQuemRecebe = computed(
  () => router.resolve({ name: 'crm_handoff_settings_index' }).href
);
</script>

<template>
  <div
    data-nota-quem-recebe
    class="flex items-start gap-3 p-3 text-sm rounded-xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
  >
    <span
      class="i-lucide-users size-5 shrink-0 mt-0.5 text-n-blue-11"
      aria-hidden="true"
    />
    <div class="flex flex-col gap-1 min-w-0">
      <p class="m-0 text-n-slate-12">
        {{ t(`${NS}.QUEM_RECEBE`, { nome }) }}
      </p>
      <a
        v-if="podeEscolherQuemRecebe"
        data-quem-recebe
        :href="linkQuemRecebe"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 font-medium underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t(`${NS}.ESCOLHER_QUEM_RECEBE`) }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
      </a>
      <p v-else-if="crmLigado" data-sem-permissao class="m-0 text-n-slate-11">
        {{ t(`${NS}.QUEM_RECEBE_SEM_PERMISSAO`) }}
      </p>
    </div>
  </div>
</template>
