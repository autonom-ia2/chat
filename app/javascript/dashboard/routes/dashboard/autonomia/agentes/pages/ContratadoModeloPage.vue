<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import ContratadosAPI from 'dashboard/api/autonomia/contratados';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import CelularConversa from '../components/CelularConversa.vue';
import DadosDaCorretoraForm from '../components/DadosDaCorretoraForm.vue';
import { MODELOS_CONTRATADOS } from '../constants/contratados';
import { erroDoContratado } from '../utils/contratado';
import { GAVETA } from '../utils/pagina';

// #3211 (Tarefa 27) — a página de um agente pronto que a corretora contrata (rota autonomia_contratado_modelo;
// mockup aprovado, estados 02 a 04): o que ele faz, o que vai pedir e uma conversa de exemplo. "Contratar" abre o
// passo 1, os dados da corretora (DadosDaCorretoraForm). O servidor cria o agente em rascunho ("Falta terminar") e a
// tela segue para a página dele com a gaveta do contratado aberta (`?gaveta=contratado`, passo 2: o acesso). A
// recusa (422) volta para o formulário, com o campo que o servidor apontou. Depois de criado, o botão continua
// ocupado até a navegação: um segundo clique criaria outro agente.
const props = defineProps({
  modelo: { type: String, required: true },
});

const { t } = useI18n();
const router = useRouter();

const conhecido = computed(() => MODELOS_CONTRATADOS.includes(props.modelo));
const aberto = ref(false);
const enviando = ref(false);
const erro = ref(null);
const formulario = ref(null);

const itensFaz = computed(() => [
  t('AGENTS.CONTRATADOS.MODELO.FAZ.DUVIDAS'),
  t('AGENTS.CONTRATADOS.MODELO.FAZ.COTA'),
  t('AGENTS.CONTRATADOS.MODELO.FAZ.ESCOLHE'),
  t('AGENTS.CONTRATADOS.MODELO.FAZ.PROPOSTA'),
]);

const itensPrecisa = computed(() => [
  { texto: t('AGENTS.CONTRATADOS.MODELO.PRECISA.DADOS') },
  {
    texto: t('AGENTS.CONTRATADOS.MODELO.PRECISA.LOGIN'),
    detalhe: t('AGENTS.CONTRATADOS.MODELO.PRECISA.LOGIN_DETALHE'),
  },
  { texto: t('AGENTS.CONTRATADOS.MODELO.PRECISA.CANAL') },
]);

// A conversa de exemplo usa um agente e uma corretora inventados (o nome de verdade é cada corretora que dá).
const nomeDoExemplo = computed(() =>
  t('AGENTS.CONTRATADOS.MODELO.EXEMPLO_NOME')
);
const corretoraDoExemplo = computed(() =>
  t('AGENTS.CONTRATADOS.MODELO.EXEMPLO_CORRETORA')
);
const conversa = computed(() => {
  const doExemplo = {
    nome: nomeDoExemplo.value,
    corretora: corretoraDoExemplo.value,
  };
  return [
    {
      de: 'cliente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.CLIENTE_1'),
      hora: '19:20',
    },
    {
      de: 'agente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.AGENTE_1', doExemplo),
      hora: '19:20',
    },
    {
      de: 'cliente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.CLIENTE_2'),
      hora: '19:21',
    },
    {
      de: 'agente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.AGENTE_2'),
      hora: '19:21',
    },
    {
      de: 'cliente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.CLIENTE_3'),
      hora: '19:22',
    },
    {
      de: 'agente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.AGENTE_3'),
      hora: '19:22',
    },
    {
      de: 'cliente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.CLIENTE_4'),
      hora: '19:24',
    },
    {
      de: 'agente',
      texto: t('AGENTS.CONTRATADOS.MODELO.CONVERSA.AGENTE_4'),
      hora: '19:25',
    },
  ];
});

const voltar = () => router.push({ name: 'autonomia_agents_builder' });

const abrir = () => {
  erro.value = null;
  aberto.value = true;
};

// Esc e o clique fora não fecham com o que a pessoa escreveu (o X continua fechando), nem enquanto contrata.
const podeFechar = () => !enviando.value && !formulario.value?.temMudanca();

const fechar = () => {
  if (enviando.value) return;
  aberto.value = false;
};

const contratar = async campos => {
  if (enviando.value) return;
  enviando.value = true;
  erro.value = null;
  let agente;
  try {
    ({ data: agente } = await ContratadosAPI.contratar(props.modelo, campos));
  } catch (falha) {
    erro.value = erroDoContratado(t, falha);
    enviando.value = false;
    return;
  }
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: agente.id },
    query: { gaveta: GAVETA.CONTRATADO },
  });
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      :data-modelo="modelo"
      class="flex flex-col w-full max-w-5xl gap-8 px-4 py-6 mx-auto md:px-6"
    >
      <button
        type="button"
        data-voltar
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('AGENTS.CONTRATADOS.MODELO.VOLTAR') }}
      </button>

      <AgenteErro
        v-if="!conhecido"
        data-modelo-desconhecido
        tom="ambar"
        :titulo="t('AGENTS.CONTRATADOS.ERRO.INDISPONIVEL')"
      />

      <template v-else>
        <AgentesHeroi
          :titulo="t('AGENTS.CONTRATADOS.MODELO.TITULO')"
          :texto="t('AGENTS.CONTRATADOS.MODELO.TEXTO')"
        >
          <template #acoes>
            <AgenteBotao
              data-contratar
              variante="branco"
              tamanho="xl"
              class="w-full md:w-auto"
              @click="abrir"
            >
              {{ t('AGENTS.CONTRATADOS.MODELO.CONTRATAR') }}
            </AgenteBotao>
          </template>
        </AgentesHeroi>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
          <div class="flex flex-col gap-6">
            <section
              class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak md:p-6"
            >
              <h2 class="m-0 text-lg font-semibold text-n-slate-12">
                {{ t('AGENTS.CONTRATADOS.MODELO.FAZ_TITULO') }}
              </h2>
              <ul class="flex flex-col gap-3 p-0 m-0 list-none">
                <li
                  v-for="item in itensFaz"
                  :key="item"
                  class="flex items-start gap-3 text-base text-n-slate-12"
                >
                  <span
                    class="i-lucide-circle-check mt-0.5 size-5 shrink-0 text-n-teal-11"
                    aria-hidden="true"
                  />
                  {{ item }}
                </li>
              </ul>
            </section>
            <section
              class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak md:p-6"
            >
              <h2 class="m-0 text-lg font-semibold text-n-slate-12">
                {{ t('AGENTS.CONTRATADOS.MODELO.PRECISA_TITULO') }}
              </h2>
              <ol class="flex flex-col gap-3 p-0 m-0 list-none">
                <li
                  v-for="(item, indice) in itensPrecisa"
                  :key="item.texto"
                  class="flex items-start gap-3 text-base text-n-slate-12"
                >
                  <span
                    aria-hidden="true"
                    class="grid text-sm font-semibold rounded-full place-items-center size-6 shrink-0 bg-n-blue-3 text-n-blue-11"
                  >
                    {{ indice + 1 }}
                  </span>
                  <span class="flex flex-col gap-0.5">
                    {{ item.texto }}
                    <span v-if="item.detalhe" class="text-sm text-n-slate-11">
                      {{ item.detalhe }}
                    </span>
                  </span>
                </li>
              </ol>
              <p
                class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-slate-2 text-n-slate-12"
              >
                <span
                  class="i-lucide-sparkles mt-0.5 size-4 shrink-0 text-n-slate-11"
                  aria-hidden="true"
                />
                {{ t('AGENTS.CONTRATADOS.MODELO.PRONTO') }}
              </p>
            </section>
          </div>
          <section class="flex flex-col gap-3">
            <h2 class="m-0 text-lg font-semibold text-n-slate-12">
              {{ t('AGENTS.CONTRATADOS.MODELO.EXEMPLO_TITULO') }}
            </h2>
            <CelularConversa
              :mensagens="conversa"
              :nome="nomeDoExemplo"
              :estado="corretoraDoExemplo"
              :rotulo-sr="t('AGENTS.CONTRATADOS.MODELO.EXEMPLO_SR')"
            />
          </section>
        </div>
        <AgenteBotao
          data-contratar-celular
          tamanho="xl"
          bloco
          class="md:hidden"
          @click="abrir"
        >
          {{ t('AGENTS.CONTRATADOS.MODELO.CONTRATAR') }}
        </AgenteBotao>
      </template>
    </div>

    <AgenteGaveta
      v-if="aberto"
      :titulo="t('AGENTS.CONTRATADOS.CONTRATAR.TITULO')"
      :pode-fechar="podeFechar"
      @fechar="fechar"
    >
      <DadosDaCorretoraForm
        ref="formulario"
        modo="contratar"
        :ocupado="enviando"
        :erro="erro"
        @enviar="contratar"
      />
      <template #rodape>
        <AgenteBotao
          data-contratar-enviar
          tamanho="xl"
          bloco
          :carregando="enviando"
          :rotulo-carregando="t('AGENTS.CONTRATADOS.CONTRATAR.ENVIANDO')"
          @click="formulario?.enviar()"
        >
          {{ t('AGENTS.CONTRATADOS.CONTRATAR.ENVIAR') }}
        </AgenteBotao>
      </template>
    </AgenteGaveta>
  </div>
</template>
