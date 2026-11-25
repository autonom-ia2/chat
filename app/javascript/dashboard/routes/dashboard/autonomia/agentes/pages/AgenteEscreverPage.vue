<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  isNavigationFailure,
  onBeforeRouteLeave,
  onBeforeRouteUpdate,
  useRouter,
} from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteConfirmacao from '../components/AgenteConfirmacao.vue';
import PapelEscolhido from '../components/PapelEscolhido.vue';
import { MODELO_DO_MEU_JEITO } from '../constants/modelos';
import { ATUACAO } from '../constants/criacao';
import { PAPEL, queryDeConversar, queryDoPapel } from '../constants/papeis';
import { MAX_INSTRUCAO, idiomaDoNavegador } from '../utils/pagina';

// #3214 — "Escrever as instruções com as minhas palavras": criar o agente direto com o texto que a pessoa já tem,
// em página inteira (rota autonomia_agents_builder com `?escrever=1`, no padrão do Conectar). O texto vale como
// escrito: o agente nasce no modo manual, parado, sem passar pelo Construtor e sem IA paga. Nasce `paused`, não
// `draft`: rascunho aparece na lista como "Falta terminar" e o "Continuar" abre o Construtor, que não serve ao
// agente escrito à mão. Parado, a lista mostra "Parado" e a página dele abre com "Editar instruções"; de lá a
// pessoa ensina, dá ferramentas, escolhe onde atende e liga.
// O campo das instruções é o da gaveta "Instruções de {nome}" (GavetaInstrucoes): mesmo limite e contador; no
// celular a caixa tem 16rem de altura (o rows="16" passaria disso) e a partir do md tem a altura da gaveta.
// O nome tem o limite do campo "Nome" da gaveta Foto e nome (GavetaFotoNome), para caber nela depois.
// A rota já exige autonomia_manage; quem só vê não chega aqui, mas a página também não oferece o formulário.
// Sair com algo escrito e sem ter criado pergunta antes (o texto se perderia). "Conte com suas palavras" vai para a
// criação conversando na mesma rota (`?modelo=custom`), então a pergunta vale também para a troca de consulta.
// Enquanto cria, ninguém sai (nem pelo navegador): a página do agente abriria por cima de onde a pessoa estivesse e,
// se a criação falhasse, o texto se perderia. Criado e a página dele não abriu: no lugar do botão fica "Abrir {nome}",
// nunca "Tentar de novo", que criaria outro agente.
// O pb-24 no celular tira o "Criar agente" de baixo da bolinha do Guia (canto de baixo à direita).
// #3219 — `papel` (a chave de constants/papeis, vinda de `?papel=` pela entrada): a faixa "Você escolheu" com "Trocar"
// (passo 1), o botão do topo vira "Voltar" (passo 2 do papel) e "Não tem um texto pronto?" vai à conversa no mesmo
// papel. O Copiloto troca o título, a frase e o exemplo (não fala de canal) e nasce interno (`actuation: 'internal'`):
// parado e sem canal, como o escrito para atender (um interno não aceita caixa). Sem `papel` (o `?escrever=1` de
// antes), a página é a de sempre.
const props = defineProps({
  papel: { type: String, default: '' },
});

const MAX_NOME = 40;
const NS = 'AGENTS.JORNADA.ESCREVER';
const INSTRUCOES = 'AGENTS.JORNADA.PAGINA.INSTRUCOES';
const ANEL_NORMAL = 'ring-n-slate-7';
const ANEL_ERRO = 'ring-n-ruby-9';
const TEXTOS_DO_PAPEL = {
  [PAPEL.COPILOTO]: 'AGENTS.JORNADA.CRIAR_EM_PASSOS.ESCREVER.COPILOTO',
};
const textoDoPapel = chave => `${TEXTOS_DO_PAPEL[props.papel] || NS}.${chave}`;

const { t, locale } = useI18n();
const router = useRouter();
const store = useStore();
const podeGerenciar = useCanManage('autonomia_manage');
const base = `escrever-${useId()}`;

const nome = ref('');
const texto = ref('');
const nomeVazio = ref(false);
const textoVazio = ref(false);
const criando = ref(false);
const criado = ref(false);
const falhou = ref(false);
const naoAbriu = ref(false);
const agenteCriado = ref(null);
const titulo = ref(null);
const campoNome = ref(null);
const campoTexto = ref(null);
const confirmarSaida = ref(null);
let saidaPendente = null;
let saidaLiberada = false;

onMounted(() => titulo.value?.focus());

const idioma = computed(() => idiomaDoNavegador(locale.value));
const contador = computed(() =>
  t(`${INSTRUCOES}.CONTADOR`, {
    n: texto.value.length.toLocaleString(idioma.value),
    max: MAX_INSTRUCAO.toLocaleString(idioma.value),
  })
);
const descricaoDoNome = computed(() =>
  [`${base}-nome-dica`, nomeVazio.value ? `${base}-erro-nome` : '']
    .filter(Boolean)
    .join(' ')
);
const descricaoDoTexto = computed(() =>
  [`${base}-dica`, textoVazio.value ? `${base}-erro` : '', `${base}-contador`]
    .filter(Boolean)
    .join(' ')
);

const aoDigitarNome = () => {
  if (nomeVazio.value && nome.value.trim()) nomeVazio.value = false;
};
const aoDigitarTexto = () => {
  if (textoVazio.value && texto.value.trim()) textoVazio.value = false;
};

// Os dois vazios mostram as duas mensagens; o foco vai para o primeiro.
const conferir = () => {
  nomeVazio.value = !nome.value.trim();
  textoVazio.value = !texto.value.trim();
  if (nomeVazio.value) campoNome.value?.focus();
  else if (textoVazio.value) campoTexto.value?.focus();
  return !nomeVazio.value && !textoVazio.value;
};

const rotaDoCriado = () => ({
  name: 'autonomia_agent_panel',
  params: { agentId: agenteCriado.value.id },
});
// -> true quando a página do agente abriu. Falha de navegação (abortada, cancelada) ou erro (o pedaço da página não
// carregou) contam como não abriu.
const abrirOCriado = async () => {
  try {
    return !isNavigationFailure(await router.replace(rotaDoCriado()));
  } catch {
    return false;
  }
};
const hrefDoCriado = computed(() =>
  agenteCriado.value ? router.resolve(rotaDoCriado()).href : ''
);
const aoAbrirCriado = async evento => {
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button) {
    return;
  }
  evento.preventDefault();
  if (await abrirOCriado()) {
    useAlert(t(`${NS}.CRIADO`, { nome: agenteCriado.value.nome }));
  }
};

// Um clique só: o botão fica "Criando…" até a página do agente abrir. Só a falha ao criar o solta; a navegação fica
// fora do try da criação, para uma falha dela nunca oferecer "Tentar de novo" e criar o agente duas vezes.
const criar = async () => {
  // Criado, um Enter no nome não cria outro.
  if (criando.value || criado.value || !conferir()) return;
  falhou.value = false;
  criando.value = true;
  let agente;
  try {
    agente = await store.dispatch('autonomiaAgents/create', {
      name: nome.value.trim(),
      agent_type: 'custom',
      mode: 'manual',
      instruction: texto.value,
      status: 'paused',
      enabled: false,
      ...(props.papel === PAPEL.COPILOTO ? { actuation: ATUACAO.INTERNA } : {}),
    });
  } catch {
    falhou.value = true;
    criando.value = false;
    return;
  }
  criado.value = true;
  agenteCriado.value = { id: agente.id, nome: nome.value.trim() };
  if (await abrirOCriado()) {
    useAlert(t(`${NS}.CRIADO`, { nome: agenteCriado.value.nome }));
    return;
  }
  naoAbriu.value = true;
  criando.value = false;
};

const temAlgoEscrito = () => Boolean(nome.value.trim() || texto.value.trim());

// Criado, sai sem perguntar (é assim que a página do agente abre). Criando, não sai e não pergunta. Com algo escrito,
// pergunta antes.
const guardarSaida = destino => {
  if (saidaLiberada || criado.value) return true;
  if (criando.value) return false;
  if (!temAlgoEscrito()) return true;
  saidaPendente = destino;
  confirmarSaida.value?.abrir();
  return false;
};
onBeforeRouteLeave(guardarSaida);
// Trocar a consulta sem sair do escrever (o mesmo `?escrever`) não é sair.
onBeforeRouteUpdate(destino =>
  destino.query?.escrever ? true : guardarSaida(destino)
);

// A licença de sair sem perguntar vale só para esta saída: se a navegação não acontecer, a próxima pergunta de novo.
const sairMesmo = async () => {
  const destino = saidaPendente;
  saidaPendente = null;
  confirmarSaida.value?.fechar();
  if (!destino) return;
  saidaLiberada = true;
  try {
    await router.replace(destino);
  } finally {
    saidaLiberada = false;
  }
};

const aoFecharConfirmacao = () => {
  saidaPendente = null;
};

const abrirCriacao = query =>
  router.push({ name: 'autonomia_agents_builder', query });
const voltar = () =>
  props.papel
    ? abrirCriacao(queryDoPapel(props.papel))
    : router.push({ name: 'autonomia_agents_index' });
const trocarPapel = () => abrirCriacao({});
const contarComMinhasPalavras = () =>
  abrirCriacao(
    props.papel
      ? queryDeConversar(props.papel)
      : { modelo: MODELO_DO_MEU_JEITO }
  );
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      data-escrever-agente
      class="flex flex-col w-full max-w-3xl gap-6 px-4 pt-6 pb-24 mx-auto md:px-6 md:pb-6"
    >
      <button
        type="button"
        data-voltar-lista
        :disabled="criando"
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 disabled:opacity-50 disabled:cursor-not-allowed"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{
          papel
            ? t('AGENTS.JORNADA.CRIAR_EM_PASSOS.COMO.VOLTAR')
            : t('AGENTS.JORNADA.CRIAR.VOLTAR')
        }}
      </button>

      <form
        :aria-labelledby="`${base}-titulo`"
        novalidate
        class="flex flex-col shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
        @submit.prevent="criar"
      >
        <div class="flex flex-col gap-5 p-5 md:p-8">
          <PapelEscolhido
            v-if="papel"
            :papel="papel"
            claro
            :desligado="criando"
            @trocar="trocarPapel"
          />
          <div class="flex flex-col gap-2">
            <h1
              :id="`${base}-titulo`"
              ref="titulo"
              tabindex="-1"
              class="m-0 text-2xl font-bold leading-tight tracking-tight outline-none text-n-slate-12"
            >
              {{ t(textoDoPapel('TITULO')) }}
            </h1>
            <p class="m-0 text-base text-n-slate-11">
              {{
                podeGerenciar
                  ? t(textoDoPapel('TEXTO'))
                  : t('AGENTS.JORNADA.HEROI.SO_VER')
              }}
            </p>
          </div>

          <template v-if="podeGerenciar">
            <div class="flex flex-col gap-1">
              <label
                :for="`${base}-nome`"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ t(`${NS}.NOME`) }}
              </label>
              <p :id="`${base}-nome-dica`" class="m-0 text-sm text-n-slate-11">
                {{ t(`${NS}.NOME_DICA`) }}
              </p>
              <input
                :id="`${base}-nome`"
                ref="campoNome"
                v-model="nome"
                data-nome
                :maxlength="MAX_NOME"
                autocomplete="off"
                :readonly="criando || criado"
                :aria-invalid="nomeVazio ? 'true' : undefined"
                :aria-describedby="descricaoDoNome"
                class="px-3 mt-1 text-base rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12"
                :class="nomeVazio ? ANEL_ERRO : ANEL_NORMAL"
                @input="aoDigitarNome"
              />
              <p
                v-if="nomeVazio"
                :id="`${base}-erro-nome`"
                role="alert"
                data-nome-vazio
                class="m-0 text-sm text-n-ruby-11"
              >
                {{ t(`${NS}.NOME_VAZIO`) }}
              </p>
            </div>

            <div class="flex flex-col gap-1">
              <label
                :for="`${base}-texto`"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ t(`${NS}.INSTRUCOES`) }}
              </label>
              <p :id="`${base}-dica`" class="m-0 text-sm text-n-slate-11">
                {{ t(`${NS}.DICA`) }}
              </p>
              <button
                type="button"
                data-contar-com-minhas-palavras
                :disabled="criando"
                class="px-0 text-sm font-semibold underline text-start min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 disabled:opacity-50 disabled:cursor-not-allowed"
                @click="contarComMinhasPalavras"
              >
                {{ t(`${NS}.SEM_TEXTO`) }}
              </button>
              <textarea
                :id="`${base}-texto`"
                ref="campoTexto"
                v-model="texto"
                data-instrucao
                rows="16"
                :maxlength="MAX_INSTRUCAO"
                :placeholder="t(textoDoPapel('EXEMPLO'))"
                :readonly="criando || criado"
                :aria-invalid="textoVazio ? 'true' : undefined"
                :aria-describedby="descricaoDoTexto"
                class="w-full h-64 min-h-[16rem] md:h-auto md:min-h-[22rem] px-3 py-2 text-base leading-relaxed rounded-xl bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12 resize-y"
                :class="textoVazio ? ANEL_ERRO : ANEL_NORMAL"
                @input="aoDigitarTexto"
              />
              <p
                v-if="textoVazio"
                :id="`${base}-erro`"
                role="alert"
                data-vazio
                class="m-0 text-sm text-n-ruby-11"
              >
                {{ t(`${INSTRUCOES}.VAZIO`) }}
              </p>
              <span
                :id="`${base}-contador`"
                class="self-end text-xs tabular-nums text-n-slate-11"
              >
                {{ contador }}
              </span>
            </div>

            <AgenteErro
              v-if="falhou"
              data-erro
              :titulo="t(`${NS}.ERRO`)"
              :garantia="t(`${NS}.ERRO_GARANTIA`)"
              :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
              :carregando="criando"
              @acao="criar"
            />
          </template>
        </div>

        <div
          v-if="podeGerenciar && !falhou"
          class="flex flex-col gap-2 px-5 py-4 border-t sm:flex-row sm:justify-end md:px-8 border-n-weak"
        >
          <a
            v-if="naoAbriu"
            data-abrir-criado
            :href="hrefDoCriado"
            class="inline-flex items-center justify-center gap-2 px-5 text-base font-semibold text-white rounded-xl min-h-12 bg-n-blue-11 dark:text-n-slate-1 hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
            @click="aoAbrirCriado"
          >
            {{ t(`${NS}.ABRIR`, { nome: agenteCriado.nome }) }}
          </a>
          <AgenteBotao
            v-else
            data-criar
            type="submit"
            tamanho="lg"
            :carregando="criando"
            :rotulo-carregando="t(`${NS}.CRIANDO`)"
          >
            {{ t(`${NS}.CRIAR`) }}
          </AgenteBotao>
        </div>
      </form>
    </div>

    <AgenteConfirmacao
      ref="confirmarSaida"
      :titulo="t(`${NS}.SAIR.TITULO`)"
      :texto="t(`${NS}.SAIR.TEXTO`)"
      :cancelar="t(`${NS}.SAIR.FICAR`)"
      :confirmar="t(`${NS}.SAIR.SAIR`)"
      :perigo="false"
      ficar-em-destaque
      @confirmar="sairMesmo"
      @fechada="aoFecharConfirmacao"
    />
  </div>
</template>
