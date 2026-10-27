<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import EscolhaComAlterar from './EscolhaComAlterar.vue';

// #2226 (ESPEC 3.2) — a tela de confirmação do que conta como resultado: os resultados que a IA
// achou na instrução, no máximo 3 visíveis, o primeiro como principal e "Alterar" em cada um (troca
// por outro da lista proposta). Uma ação: Confirmar. O painel funciona sem esta confirmação.
const props = defineProps({
  nome: { type: String, required: true },
  propostos: { type: Array, required: true },
});

const emit = defineEmits(['fechar', 'confirmar']);

const { t } = useI18n();
const NS = 'AGENTS.DESEMPENHO.MARCOS';
const VISIVEIS = 3;

const escolhidos = ref(
  props.propostos.slice(0, VISIVEIS).map(marco => marco.id)
);

const opcoes = computed(() =>
  props.propostos.map(marco => ({ value: marco.id, label: marco.nome }))
);

const trocar = (posicao, id) => {
  escolhidos.value = escolhidos.value.map((atual, i) =>
    i === posicao ? id : atual
  );
};

const confirmar = () =>
  emit(
    'confirmar',
    escolhidos.value.map(id => props.propostos.find(marco => marco.id === id))
  );
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <p class="m-0 text-sm text-n-slate-12">{{ t(`${NS}.TEXTO`, { nome }) }}</p>
    <ol
      data-marcos
      :aria-label="t(`${NS}.LISTA`, { nome })"
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li
        v-for="(id, posicao) in escolhidos"
        :key="posicao"
        data-marco
        class="flex flex-col gap-1 p-4 rounded-xl ring-1 ring-inset"
        :class="
          posicao === 0
            ? 'bg-n-blue-2 ring-n-blue-6'
            : 'bg-n-solid-1 ring-n-weak dark:ring-n-slate-6'
        "
      >
        <span class="text-xs font-semibold text-n-slate-11">
          {{ posicao === 0 ? t(`${NS}.PRINCIPAL`) : t(`${NS}.TAMBEM`) }}
        </span>
        <EscolhaComAlterar
          :model-value="id"
          :opcoes="opcoes"
          :rotulo="t(`${NS}.ESCOLHA`)"
          @update:model-value="trocar(posicao, $event)"
        />
      </li>
    </ol>
    <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.NOTA`) }}</p>
    <template #rodape>
      <AgenteBotao data-confirmar bloco @click="confirmar">
        {{ t(`${NS}.CONFIRMAR`) }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
