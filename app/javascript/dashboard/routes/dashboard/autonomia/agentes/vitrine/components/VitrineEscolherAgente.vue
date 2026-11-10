<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../components/AgenteBotao.vue';
import AgenteGaveta from '../../components/AgenteGaveta.vue';
import EscolhaRadio from '../../components/EscolhaRadio.vue';

// #2858 F2 (decisão do Rodrigo) — "Criar a minha (avançado)" pergunta primeiro em qual agente. Depois a página leva
// às ferramentas daquele agente, já no cadastro novo. `agentes` já vem sem a Lia (cotação).
const props = defineProps({
  agentes: { type: Array, required: true },
  agenteInicial: { type: [Number, String], default: null },
});

const emit = defineEmits(['fechar', 'escolhido']);

const NS = 'AGENTS.VITRINE.CRIAR_MINHA';
const { t } = useI18n();

const inicial = props.agentes.find(
  agente => agente.id === Number(props.agenteInicial)
);
const agenteId = ref(inicial ? inicial.id : (props.agentes[0]?.id ?? null));

const opcoes = computed(() =>
  props.agentes.map(agente => ({ valor: agente.id, titulo: agente.name }))
);
const escolhido = computed(() =>
  props.agentes.find(agente => agente.id === agenteId.value)
);

const continuar = () => {
  if (escolhido.value) emit('escolhido', escolhido.value);
};
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <p class="m-0 text-base text-n-slate-12">{{ t(`${NS}.TEXTO`) }}</p>
    <EscolhaRadio
      v-model="agenteId"
      data-vitrine-criar-agentes
      :rotulo="t(`${NS}.TITULO`)"
      :opcoes="opcoes"
    />
    <template #rodape>
      <AgenteBotao
        data-vitrine-criar-continuar
        tamanho="lg"
        bloco
        icone-direita="i-lucide-arrow-right"
        :inativo="!escolhido"
        @click="continuar"
      >
        {{
          escolhido
            ? t(`${NS}.CONTINUAR`, { nome: escolhido.name })
            : t(`${NS}.ESCOLHA`)
        }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
