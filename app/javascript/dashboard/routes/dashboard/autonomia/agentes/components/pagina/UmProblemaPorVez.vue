<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import EscolhaRadio from '../EscolhaRadio.vue';

// #1426 (tema 4b) — "um problema por vez": o que as conferências e o autoteste acharam no material,
// um cartão de cada vez, com "1 de N", uma explicação simples e no máximo duas saídas. Nada trava:
// "Pular por agora" passa para o próximo, e o agente segue atendendo com o resto do material.
// Tipos: vazio, ocr (foto ilegível), duplicado, sem_cabecalho (tabela sem títulos), contradicao e
// autoteste (resposta errada no autoteste). Quem só vê lê o cartão, sem as ações.
const props = defineProps({
  problemas: { type: Array, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  // O problema que está sendo resolvido (o botão mostra que está salvando).
  resolvendo: { type: String, default: '' },
});

const emit = defineEmits(['resolver', 'mandarOutro', 'tirar', 'corrigir']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.MATERIAL.PROBLEMA';

const indice = ref(0);
const escolha = ref(null);

const atual = computed(
  () => props.problemas[Math.min(indice.value, props.problemas.length - 1)]
);

watch(
  () => props.problemas.length,
  total => {
    if (indice.value >= total) indice.value = 0;
  }
);
watch(
  () => atual.value?.id,
  () => {
    escolha.value = null;
  }
);

const pular = () => {
  indice.value = (indice.value + 1) % props.problemas.length;
};

const chave = computed(() => (atual.value?.tipo || '').toUpperCase());
const dados = computed(() => ({ ...atual.value, agente: props.nome }));

const opcoesDaContradicao = computed(() =>
  (atual.value?.opcoes || []).map(opcao => ({
    valor: opcao.valor,
    titulo: opcao.diz,
    texto: t(`${NS}.CONTRADICAO.ONDE`, { onde: opcao.onde }),
  }))
);

const salvando = computed(() => props.resolvendo === atual.value?.id);
const resolver = valor => emit('resolver', atual.value.id, valor);
const fonte = computed(() => atual.value?.fontes?.[0]);
</script>

<template>
  <section
    v-if="atual"
    data-um-problema
    :data-tipo="atual.tipo"
    :aria-label="t(`${NS}.ROTULO`)"
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
  >
    <p
      class="flex items-center gap-2 m-0 text-xs font-semibold uppercase text-n-amber-11"
    >
      <span class="i-lucide-hand size-4" aria-hidden="true" />
      <span data-contagem>
        {{
          t(`${NS}.CONTAGEM`, { atual: indice + 1, total: problemas.length })
        }}
      </span>
    </p>
    <h3 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.${chave}.TITULO`, dados) }}
    </h3>
    <p class="m-0 text-sm text-n-slate-12">
      {{ t(`${NS}.${chave}.TEXTO`, dados) }}
    </p>

    <ul
      v-if="atual.tipo === 'sem_cabecalho'"
      data-amostra
      :aria-label="t(`${NS}.SEM_CABECALHO.AMOSTRA`)"
      class="flex flex-wrap gap-1 p-0 m-0 list-none"
    >
      <li
        v-for="(celula, i) in atual.amostra"
        :key="i"
        class="px-2 py-1 font-mono text-xs rounded-md bg-n-solid-1 ring-1 ring-inset ring-n-weak text-n-slate-12"
      >
        {{ celula }}
      </li>
    </ul>

    <dl
      v-if="atual.tipo === 'autoteste'"
      class="flex flex-col gap-1 p-3 m-0 text-sm rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
    >
      <dt class="font-semibold text-n-slate-11">
        {{ t(`${NS}.AUTOTESTE.PERGUNTA`) }}
      </dt>
      <dd class="m-0 text-n-slate-12">{{ atual.pergunta }}</dd>
      <dt class="font-semibold text-n-slate-11">
        {{ t(`${NS}.AUTOTESTE.RESPONDEU`, { agente: nome }) }}
      </dt>
      <dd class="m-0 text-n-slate-12">{{ atual.resposta }}</dd>
      <dt class="font-semibold text-n-slate-11">
        {{ t(`${NS}.AUTOTESTE.MATERIAL`) }}
      </dt>
      <dd class="m-0 text-n-slate-12">{{ atual.material }}</dd>
    </dl>

    <EscolhaRadio
      v-if="atual.tipo === 'contradicao' && podeGerenciar"
      v-model="escolha"
      :rotulo="t(`${NS}.CONTRADICAO.QUAL`)"
      :opcoes="opcoesDaContradicao"
    />

    <div v-if="podeGerenciar" data-acoes class="flex flex-wrap gap-2">
      <template v-if="atual.tipo === 'vazio' || atual.tipo === 'ocr'">
        <AgenteBotao
          data-acao="mandar-outro"
          @click="emit('mandarOutro', fonte)"
        >
          {{ t(`${NS}.${chave}.MANDAR`) }}
        </AgenteBotao>
        <AgenteBotao
          v-if="atual.tipo === 'vazio'"
          data-acao="tirar"
          variante="contorno"
          @click="emit('tirar', fonte)"
        >
          {{ t(`${NS}.VAZIO.TIRAR`) }}
        </AgenteBotao>
        <AgenteBotao
          v-else
          data-acao="escrever"
          variante="contorno"
          @click="emit('corrigir', null)"
        >
          {{ t(`${NS}.OCR.ESCREVER`) }}
        </AgenteBotao>
      </template>
      <template v-else-if="atual.tipo === 'duplicado'">
        <AgenteBotao
          data-acao="um-so"
          :carregando="salvando"
          @click="resolver('um_so')"
        >
          {{ t(`${NS}.DUPLICADO.UM_SO`, dados) }}
        </AgenteBotao>
        <AgenteBotao
          data-acao="os-dois"
          variante="contorno"
          :inativo="salvando"
          @click="resolver('os_dois')"
        >
          {{ t(`${NS}.DUPLICADO.OS_DOIS`) }}
        </AgenteBotao>
      </template>
      <template v-else-if="atual.tipo === 'sem_cabecalho'">
        <AgenteBotao
          data-acao="mandar-outro"
          @click="emit('mandarOutro', fonte)"
        >
          {{ t(`${NS}.SEM_CABECALHO.MANDAR`) }}
        </AgenteBotao>
        <AgenteBotao
          data-acao="explicar"
          variante="contorno"
          @click="emit('corrigir', null)"
        >
          {{ t(`${NS}.SEM_CABECALHO.EXPLICAR`) }}
        </AgenteBotao>
      </template>
      <AgenteBotao
        v-else-if="atual.tipo === 'contradicao'"
        data-acao="usar"
        :inativo="escolha === null"
        :carregando="salvando"
        @click="resolver(escolha)"
      >
        {{ t(`${NS}.CONTRADICAO.USAR`) }}
      </AgenteBotao>
      <template v-else-if="atual.tipo === 'autoteste'">
        <AgenteBotao
          data-acao="corrigir"
          @click="
            emit('corrigir', {
              pergunta: atual.pergunta,
              resposta: atual.resposta,
            })
          "
        >
          {{ t(`${NS}.AUTOTESTE.CORRIGIR`) }}
        </AgenteBotao>
        <AgenteBotao
          data-acao="certa"
          variante="contorno"
          :carregando="salvando"
          @click="resolver('certa')"
        >
          {{ t(`${NS}.AUTOTESTE.CERTA`) }}
        </AgenteBotao>
      </template>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.CONTINUA`, { agente: nome }) }}
      </p>
      <button
        v-if="problemas.length > 1"
        type="button"
        data-pular
        class="px-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="pular"
      >
        {{ t(`${NS}.PULAR`) }}
      </button>
    </div>
  </section>
</template>
