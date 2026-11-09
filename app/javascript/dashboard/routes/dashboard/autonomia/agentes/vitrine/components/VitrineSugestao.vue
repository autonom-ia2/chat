<script setup>
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import { ferramentaPorId } from '../catalogo';

// #2776 J6 — para o agente que já existe: um cartão discreto com UMA ferramenta da vitrine que combina com o que ele
// faz, e um toque para incluir. Quem escolhe é o modelo, pelo sentido das instruções do agente (no protótipo, dado
// fictício). "Agora não" some com o cartão; nada é incluído sem o toque.
const props = defineProps({
  nome: { type: String, required: true },
  ferramentaId: { type: String, required: true },
});

const emit = defineEmits(['incluir', 'dispensar']);

const NS = 'AGENTS.VITRINE';
const { t } = useI18n();
const ferramenta = () => t(`${NS}.FERRAMENTAS.${props.ferramentaId}.NOME`);
</script>

<template>
  <aside
    data-vitrine-sugestao
    :aria-label="t(`${NS}.SUGESTAO.ROTULO`)"
    class="flex flex-wrap items-center gap-3 px-4 py-3 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-5"
  >
    <span
      aria-hidden="true"
      class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-blue-3 text-n-blue-11"
    >
      <span
        :class="ferramentaPorId(ferramentaId)?.icone || 'i-lucide-sparkles'"
        class="size-5"
      />
    </span>
    <p class="flex-1 m-0 text-sm min-w-48 text-n-slate-12">
      {{ t(`${NS}.SUGESTAO.TEXTO`, { nome, ferramenta: ferramenta() }) }}
    </p>
    <div class="flex items-center gap-2">
      <AgenteBotao
        data-vitrine-sugestao-incluir
        icone="i-lucide-plus"
        @click="emit('incluir')"
      >
        {{ t(`${NS}.SUGESTAO.INCLUIR`) }}
      </AgenteBotao>
      <AgenteBotao
        data-vitrine-sugestao-dispensar
        variante="fantasma"
        @click="emit('dispensar')"
      >
        {{ t(`${NS}.SUGESTAO.AGORA_NAO`) }}
      </AgenteBotao>
    </div>
  </aside>
</template>
