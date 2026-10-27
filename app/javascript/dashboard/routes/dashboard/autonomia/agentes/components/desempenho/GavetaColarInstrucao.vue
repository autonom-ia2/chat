<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';

// #2226 (ESPEC 2.12 e 6.8) — colar a instrução do agente de outro sistema. Só quem gerencia os
// agentes. Aviso "Não cole senhas nem chaves". No protótipo, salvar só troca a tela para "com
// instrução colada"; gravar e extrair as regras curtas chega no PR 9.
defineProps({
  nome: { type: String, required: true },
});

const emit = defineEmits(['fechar', 'salvar']);

const { t } = useI18n();
const NS = 'AGENTS.DESEMPENHO.INSTRUCAO';
const texto = ref('');
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`, { nome })" @fechar="emit('fechar')">
    <p class="m-0 text-sm text-n-slate-12">{{ t(`${NS}.TEXTO`, { nome }) }}</p>
    <label class="flex flex-col gap-2 text-sm font-semibold text-n-slate-12">
      {{ t(`${NS}.CAMPO`, { nome }) }}
      <textarea
        v-model="texto"
        data-campo-instrucao
        rows="10"
        class="w-full p-3 text-sm font-normal rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
      />
    </label>
    <p class="flex items-start gap-2 m-0 text-sm text-n-slate-12">
      <span
        class="i-lucide-lock size-4 mt-0.5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.NAO_COLE`) }}
    </p>
    <template #rodape>
      <AgenteBotao
        data-salvar
        bloco
        :desabilitado="!texto.trim()"
        @click="emit('salvar')"
      >
        {{ t(`${NS}.SALVAR`) }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
