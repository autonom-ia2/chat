<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import AgenteBotao from './AgenteBotao.vue';

// #1648 (mockup-2) — a chave de acesso do agente de outro sistema (access_token do agent_bot),
// escondida por padrão, com Mostrar e Copiar. Mesma função do AccessToken de Configurações › Robôs,
// sem o componente global legado (woot-input) e com alvo de toque de 44 px.
const props = defineProps({
  valor: { type: String, required: true },
});

const { t } = useI18n();
const visivel = ref(false);
const texto = computed(() =>
  visivel.value ? props.valor : '•'.repeat(Math.min(props.valor.length, 24))
);

const copiar = async () => {
  await copyTextToClipboard(props.valor);
  useAlert(t('AGENTS.OUTRO_SISTEMA.COPIOU'));
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('AGENTS.OUTRO_SISTEMA.CHAVE') }}
    </span>
    <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
      <code
        data-chave
        class="flex items-center min-w-0 px-3 py-2 overflow-hidden font-mono text-sm rounded-xl min-h-11 grow bg-n-slate-2 text-n-slate-12 ring-1 ring-inset ring-n-weak text-ellipsis whitespace-nowrap"
      >
        {{ texto }}
      </code>
      <div class="flex gap-2 shrink-0">
        <AgenteBotao
          variante="contorno"
          :icone="visivel ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          @click="visivel = !visivel"
        >
          {{
            visivel
              ? t('AGENTS.OUTRO_SISTEMA.ESCONDER')
              : t('AGENTS.OUTRO_SISTEMA.MOSTRAR')
          }}
        </AgenteBotao>
        <AgenteBotao variante="contorno" icone="i-lucide-copy" @click="copiar">
          {{ t('AGENTS.OUTRO_SISTEMA.COPIAR') }}
        </AgenteBotao>
      </div>
    </div>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.OUTRO_SISTEMA.CHAVE_AJUDA') }}
    </p>
  </div>
</template>
