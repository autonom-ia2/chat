<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import CriarEmPassos from '../components/CriarEmPassos.vue';
import { papelDoPasso } from '../constants/papeis';

// #3219 — a página "Criar agente" em dois passos (o que ele vai fazer, depois como começar), aberta pela
// AgentesCriarEntrada quando a URL não pede outro começo. No passo 1 o botão do topo é "Voltar para Agentes"; no passo 2
// (`?papel=` na URL) é "Voltar" e leva ao passo 1. Repassa a escolha final à entrada.
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const noPasso2 = computed(() => !!papelDoPasso(route.query));
const voltar = () =>
  noPasso2.value
    ? router.push({ query: {} })
    : router.push({ name: 'autonomia_agents_index' });
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      data-criar-agente-em-passos
      class="flex flex-col w-full max-w-5xl gap-8 px-4 py-6 mx-auto md:px-6"
    >
      <button
        type="button"
        data-voltar-lista
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{
          noPasso2
            ? t('AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO.VOLTAR')
            : t('AGENTS.JORNADA.CRIAR.VOLTAR')
        }}
      </button>
      <CriarEmPassos @escolher="query => emit('escolher', query)" />
    </div>
  </div>
</template>
