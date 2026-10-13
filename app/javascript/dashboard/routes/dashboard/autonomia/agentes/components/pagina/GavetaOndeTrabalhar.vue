<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import EscolhaRadio from '../EscolhaRadio.vue';

// #1366 (protótipo da Fase 2, #1424) — ligar um agente que não tem onde trabalhar começa aqui, nunca
// "no vazio". Passo 1: onde ele vai trabalhar (canal, equipe ou ajudar outro agente). Passo 2:
//  - canal: a página abre a escolha de canal de sempre (GavetaOndeQuando, modo voltar);
//  - equipe: quem cuida do quê é escolhido por CAIXA e FUNIL no CRM ("Caixas no CRM › Quem cuida
//    do quê?", vocabulário do Multifunil); aqui só leva até lá;
//  - ajuda: escolhe o agente que ele vai ajudar e confirma (papel pelo adaptador, ver prototipo/fonte).
const props = defineProps({
  nome: { type: String, required: true },
  // Agentes que este pode ajudar: [{ id, name }]
  outros: { type: Array, default: () => [] },
  // (papel) => Promise: grava o papel e liga o agente; quem chama decide como.
  confirmar: { type: Function, required: true },
});

const emit = defineEmits(['fechar', 'canal', 'pronto']);

const { t } = useI18n();
const router = useRouter();
const NS = 'AGENTS.JORNADA.ONDE_TRABALHAR';

const lugar = ref(null);
const passo = ref(1);
const ajudado = ref(null);
const salvando = ref(false);
const falhou = ref(false);

const opcoes = computed(() =>
  ['canal', 'equipe', 'ajuda'].map(valor => ({
    valor,
    titulo: t(`${NS}.${valor.toUpperCase()}.TITULO`),
    texto: t(`${NS}.${valor.toUpperCase()}.TEXTO`),
  }))
);

const opcoesDeAjuda = computed(() =>
  props.outros.map(agente => ({ valor: agente.id, titulo: agente.name }))
);

const nomeDoAjudado = computed(
  () => props.outros.find(agente => agente.id === ajudado.value)?.name || ''
);

const linkCaixas = computed(() => router.resolve({ name: 'crm_caixas' }).href);

const continuar = () => {
  if (!lugar.value) return;
  if (lugar.value === 'canal') {
    emit('canal');
    return;
  }
  passo.value = 2;
};

const voltar = () => {
  passo.value = 1;
  falhou.value = false;
};

const comecarAAjudar = async () => {
  if (!ajudado.value || salvando.value) return;
  salvando.value = true;
  falhou.value = false;
  try {
    const papel = { tipo: 'ajuda', agente: nomeDoAjudado.value };
    await props.confirmar(papel);
    emit('pronto', papel);
  } catch {
    falhou.value = true;
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`, { nome })" @fechar="emit('fechar')">
    <template v-if="passo === 1">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.TEXTO`, { nome }) }}
      </p>
      <EscolhaRadio
        v-model="lugar"
        data-onde-trabalhar
        :rotulo="t(`${NS}.ROTULO`)"
        :opcoes="opcoes"
      />
    </template>

    <template v-else-if="lugar === 'equipe'">
      <div
        data-passo-equipe
        class="flex flex-col gap-3 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
      >
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.EQUIPE_PASSO.TITULO`) }}
        </p>
        <p class="m-0 text-sm text-n-slate-12">
          {{ t(`${NS}.EQUIPE_PASSO.TEXTO`, { nome }) }}
        </p>
      </div>
    </template>

    <template v-else>
      <p
        v-if="opcoesDeAjuda.length"
        class="m-0 text-base font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.AJUDA_PASSO.ROTULO`, { nome }) }}
      </p>
      <EscolhaRadio
        v-if="opcoesDeAjuda.length"
        v-model="ajudado"
        data-passo-ajuda
        :rotulo="t(`${NS}.AJUDA_PASSO.ROTULO`, { nome })"
        :opcoes="opcoesDeAjuda"
      />
      <p v-else class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.AJUDA_PASSO.NENHUM`) }}
      </p>
      <AgenteErro v-if="falhou" :titulo="t(`${NS}.ERRO`, { nome })" />
    </template>

    <template #rodape>
      <AgenteBotao
        v-if="passo === 1"
        data-continuar-onde
        tamanho="lg"
        bloco
        icone-direita="i-lucide-arrow-right"
        :inativo="!lugar"
        @click="continuar"
      >
        {{ t(`${NS}.CONTINUAR`) }}
      </AgenteBotao>
      <a
        v-else-if="lugar === 'equipe'"
        data-abrir-caixas
        :href="linkCaixas"
        class="inline-flex items-center justify-center w-full gap-2 px-5 text-base font-semibold text-white rounded-xl min-h-12 bg-n-blue-11 dark:text-n-slate-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      >
        {{ t(`${NS}.EQUIPE_PASSO.ABRIR`) }}
        <span class="i-lucide-arrow-right size-5" aria-hidden="true" />
      </a>
      <AgenteBotao
        v-else
        data-comecar-ajudar
        tamanho="lg"
        bloco
        :inativo="!ajudado"
        :carregando="salvando"
        @click="comecarAAjudar"
      >
        {{ t(`${NS}.AJUDA_PASSO.CONFIRMAR`) }}
      </AgenteBotao>
      <AgenteBotao
        v-if="passo === 2"
        data-voltar-onde
        variante="fantasma"
        bloco
        icone="i-lucide-arrow-left"
        @click="voltar"
      >
        {{ t(`${NS}.VOLTAR`) }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
