<script setup>
import { computed, nextTick, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AgentesEtapas from '../components/AgentesEtapas.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import FotoDoAgente from '../components/FotoDoAgente.vue';
import ChaveDeAcesso from '../components/ChaveDeAcesso.vue';

// #1648 (mockup-2, ajuste do Rodrigo) — "Conectar agente de outro sistema" em página inteira, no
// padrão do "Criar agente" (rota autonomia_agents_builder com `?conectar=outro`). Três etapas:
// 1. Quem é: foto, nome e "O que ele faz"; 2. Endereço do webhook (Conectar cria o agent_bot);
// 3. "Falta um passo: copie a chave", com Concluir, que abre a página do agente.
const NS = 'AGENTS.OUTRO_SISTEMA';
const PG = 'AGENTS.OUTRO_SISTEMA.CONECTAR_PAGINA';
const { t } = useI18n();
const router = useRouter();
const store = useStore();

const passo = ref(1);
const conectando = ref(false);
const criado = ref(null);
const titulo = ref(null);
const form = reactive({
  nome: '',
  descricao: '',
  endereco: '',
  foto: null,
  fotoUrl: '',
});

const nomesDasEtapas = computed(() => [
  t(`${PG}.ETAPA_NOME`),
  t(`${PG}.ETAPA_ENDERECO`),
  t(`${PG}.ETAPA_CHAVE`),
]);
const TITULOS = { 1: 'PASSO1_TITULO', 2: 'PASSO2_TITULO', 3: 'PASSO3_TITULO' };

const irPara = async numero => {
  passo.value = numero;
  await nextTick();
  titulo.value?.focus();
};

const aoEscolherFoto = ({ file, url }) => {
  form.foto = file;
  form.fotoUrl = url;
};

const voltarParaLista = () => router.push({ name: 'autonomia_agents_index' });

const conectar = async () => {
  if (conectando.value) return;
  conectando.value = true;
  try {
    criado.value = await store.dispatch('agentBots/create', {
      name: form.nome,
      description: form.descricao,
      outgoing_url: form.endereco,
      bot_type: 'webhook',
      avatar: form.foto,
    });
    irPara(3);
  } catch {
    useAlert(t(`${PG}.ERRO`));
  } finally {
    conectando.value = false;
  }
};

const concluir = () =>
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: criado.value.id },
    query: { origem: 'webhook' },
  });
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      data-conectar-outro
      class="flex flex-col w-full max-w-3xl gap-6 px-4 py-6 mx-auto md:px-6"
    >
      <button
        v-if="passo < 3"
        type="button"
        data-voltar-lista
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="voltarParaLista"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${PG}.VOLTAR`) }}
      </button>
      <div class="flex flex-col gap-3">
        <p class="m-0 text-sm font-semibold text-n-slate-11">
          {{ t(`${PG}.TITULO`) }}
        </p>
        <AgentesEtapas :atual="passo" :nomes="nomesDasEtapas" />
      </div>

      <section
        aria-labelledby="conectar-titulo"
        class="flex flex-col shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
      >
        <div class="flex flex-col gap-5 p-5 md:p-8">
          <span
            v-if="passo === 3"
            aria-hidden="true"
            class="grid rounded-full place-items-center size-12 bg-n-teal-9 text-white dark:text-n-slate-1"
          >
            <span class="i-lucide-check size-6" />
          </span>
          <div class="flex flex-col gap-2">
            <h1
              id="conectar-titulo"
              ref="titulo"
              tabindex="-1"
              class="m-0 text-2xl font-bold leading-tight tracking-tight outline-none text-n-slate-12"
            >
              {{ t(`${PG}.${TITULOS[passo]}`) }}
            </h1>
            <p v-if="passo === 1" class="m-0 text-base text-n-slate-11">
              {{ t(`${NS}.EXPLICA`) }}
            </p>
            <p v-else-if="passo === 2" class="m-0 text-base text-n-slate-11">
              {{ t(`${PG}.PASSO2_TEXTO`) }}
            </p>
            <p v-else class="m-0 text-base text-n-slate-11">
              {{ t(`${PG}.PASSO3_TEXTO`, { nome: form.nome }) }}
            </p>
          </div>

          <template v-if="passo === 1">
            <FotoDoAgente
              :nome="form.nome"
              :src="form.fotoUrl"
              @escolher="aoEscolherFoto"
            />
            <Input
              id="conectar-nome"
              v-model="form.nome"
              :label="t(`${NS}.NOME`)"
              :placeholder="t(`${NS}.NOME_EXEMPLO`)"
            />
            <TextArea
              id="conectar-descricao"
              v-model="form.descricao"
              :label="t(`${NS}.DESCRICAO`)"
              :placeholder="t(`${NS}.DESCRICAO_EXEMPLO`)"
            />
          </template>
          <Input
            v-else-if="passo === 2"
            id="conectar-endereco"
            v-model="form.endereco"
            type="url"
            :label="t(`${NS}.ENDERECO`)"
            placeholder="https://"
            :message="t(`${NS}.ENDERECO_AJUDA`)"
          />
          <template v-else>
            <ChaveDeAcesso :valor="criado?.access_token || ''" />
            <p
              class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-slate-12"
            >
              <span
                class="i-lucide-info size-5 shrink-0 text-n-blue-11"
                aria-hidden="true"
              />
              {{ t(`${PG}.PASSO3_DEPOIS`, { nome: form.nome }) }}
            </p>
          </template>
        </div>

        <div
          class="flex flex-col-reverse gap-2 px-5 py-4 border-t sm:flex-row sm:justify-end md:px-8 border-n-weak"
        >
          <AgenteBotao
            v-if="passo === 2"
            data-voltar-passo
            variante="contorno"
            tamanho="lg"
            :desabilitado="conectando"
            @click="irPara(1)"
          >
            {{ t(`${PG}.VOLTAR_PASSO`) }}
          </AgenteBotao>
          <AgenteBotao
            v-if="passo === 1"
            data-continuar
            tamanho="lg"
            icone-direita="i-lucide-arrow-right"
            :desabilitado="!form.nome.trim()"
            @click="irPara(2)"
          >
            {{ t(`${PG}.CONTINUAR`) }}
          </AgenteBotao>
          <AgenteBotao
            v-else-if="passo === 2"
            data-conectar
            tamanho="lg"
            :carregando="conectando"
            :desabilitado="!form.endereco.trim()"
            @click="conectar"
          >
            {{ t(`${NS}.BOTAO_CONECTAR`) }}
          </AgenteBotao>
          <AgenteBotao v-else data-concluir tamanho="lg" @click="concluir">
            {{ t(`${NS}.CONCLUIR`) }}
          </AgenteBotao>
        </div>
      </section>
    </div>
  </div>
</template>
