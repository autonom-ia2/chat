<script setup>
import { getCurrentInstance } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import CelularConversa from '../components/CelularConversa.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import OndeQuandoEscolha from '../components/OndeQuandoEscolha.vue';
import RamosProntos from '../components/RamosProntos.vue';
import PaginaHeroi from '../components/pagina/PaginaHeroi.vue';
import { MODELOS } from '../constants/modelos';
import { MODELOS_DE_RAMO, TOM_DO_RAMO } from '../constants/modelosDeRamo';
import { ESTADO } from '../utils/estadoDoAgente';

// #3211 (Tarefa 24) — mockup do agente pronto "Seguro Viagem Universal", para o Rodrigo aprovar a jornada em prints
// antes de qualquer tela de verdade. Monta com os componentes reais da área de Agentes; os textos ficam aqui, soltos,
// porque é só a história. Dados fictícios: a agente "Bia" da "Corretora Exemplo". Nenhum login de verdade.
// Rodada 2 (diretor de arte, 6,5/10): o cartão vem primeiro, em "Vendem sozinhos", acima dos ramos; passos 1 a 3 nas
// gavetas; a página da Bia ganha o bloco "Corretora e acesso"; estados novos (Universal fora do ar, atendendo,
// página em repouso, alterar a corretora, acesso recusado meses depois).
// A gaveta "Onde" é montada aqui com o OndeQuandoEscolha de verdade, porque a GavetaOndeQuando ainda não tem o
// "Passo 3 de 3" nem a caixa livre única já marcada: os dois entram na Tarefa 28.
const { t } = useI18n();
useI18n().locale.value = 'pt_BR';

// O Teleport da gaveta e a escolha de canal leem a loja; fora do painel (Histoire), uma loja mínima de mentira.
const globais = getCurrentInstance().appContext.config.globalProperties;
if (!globais.$store) {
  const getters = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 1, accounts: [{ id: 1, role: 'administrator' }] },
    getCurrentCustomRoleId: null,
    'accounts/isRTL': false,
    'accounts/getAccount': () => ({ id: 1, features: {} }),
    'accounts/isFeatureEnabledonAccount': () => false,
    'globalConfig/get': {},
  };
  globais.$store = { getters, dispatch: () => Promise.resolve() };
}

const NOME = 'Bia';
const CORRETORA = 'Corretora Exemplo';
const SOBRE =
  'Corretora em Campinas desde 2010. Atendemos famílias e empresas, com seguro viagem para o mundo todo.';
const CANAL = 'WhatsApp Vendas';

const FAZ = [
  'Tira as dúvidas do viajante com as regras oficiais da Universal',
  'Cota na hora, com o destino, as datas e a idade de cada um',
  'Ajuda a escolher o plano e explica o que cada um cobre',
  'Monta a proposta e manda o link de pagamento',
];

const PRECISA = [
  {
    texto: 'Um nome para o agente e uma frase sobre a sua corretora',
  },
  {
    texto: 'O login e a senha do portal da Universal',
    detalhe: 'É o mesmo que você usa no site da Universal.',
  },
  { texto: 'Um canal para atender, como o WhatsApp' },
];

const CONVERSA = [
  {
    de: 'cliente',
    texto: 'Oi! Quero seguro para Portugal, de 10 a 24 de janeiro. Somos 2.',
    hora: '19:20',
  },
  {
    de: 'agente',
    texto: 'Oi! Eu sou a Bia, da Corretora Exemplo. Quantos anos cada um tem?',
    hora: '19:20',
  },
  { de: 'cliente', texto: '45 e 43', hora: '19:21' },
  {
    de: 'agente',
    texto:
      'Para vocês dois, o plano mais escolhido para a Europa sai R$ 189,90 por pessoa. Quer esse?',
    hora: '19:21',
  },
  { de: 'cliente', texto: 'Quero', hora: '19:22' },
  {
    de: 'agente',
    texto:
      'Para a proposta, me manda o nome completo, CPF e data de nascimento de cada um.',
    hora: '19:22',
  },
  {
    de: 'cliente',
    texto:
      'Ana Lima, 000.000.000-00, 02/03/1980\nJoão Lima, 000.000.000-00, 15/07/1982',
    hora: '19:24',
  },
  {
    de: 'agente',
    texto: 'Pronto! Este é o link para pagar: pagamento.exemplo.com.br/a1b2',
    hora: '19:25',
  },
];

// Uma caixa livre só: ela já vem marcada.
const CANAIS = [
  {
    inbox_id: 11,
    name: CANAL,
    channel_type: 'Channel::Whatsapp',
    occupied_by: null,
  },
  {
    inbox_id: 12,
    name: 'Instagram',
    channel_type: 'Channel::Instagram',
    occupied_by: {
      kind: 'agent',
      agent_id: 5,
      agent_name: 'Leo',
      operating: true,
      caixas: 2,
    },
  },
];
const HORARIOS = { 11: 'seg. a sex., 9h às 18h', 12: null };

// tela: area | modelo | agente.
// modelo → dados: ok | erro. agente → acesso (gaveta do acesso), gaveta: onde | corretora, pagina: o aviso no topo.
// `ligada`: a Bia já atende (depois do "Começar a atender").
const VARIANTES = [
  { id: '01', titulo: '01 · Criar agente: Vendem sozinhos', tela: 'area' },
  { id: '02', titulo: '02 · Página do modelo', tela: 'modelo' },
  {
    id: '03',
    titulo: '03 · Passo 1: a corretora',
    tela: 'modelo',
    dados: 'ok',
  },
  {
    id: '04',
    titulo: '04 · Passo 1: a corretora com erro',
    tela: 'modelo',
    dados: 'erro',
  },
  {
    id: '05',
    titulo: '05 · Passo 2: acesso vazio',
    tela: 'agente',
    acesso: 'vazio',
  },
  {
    id: '06',
    titulo: '06 · Passo 2: acesso sem preencher',
    tela: 'agente',
    acesso: 'faltando',
  },
  {
    id: '07',
    titulo: '07 · Passo 2: conferindo',
    tela: 'agente',
    acesso: 'conferindo',
  },
  {
    id: '08',
    titulo: '08 · Passo 2: Universal fora do ar',
    tela: 'agente',
    acesso: 'indisponivel',
  },
  {
    id: '09',
    titulo: '09 · Passo 2: acesso conferido',
    tela: 'agente',
    acesso: 'ok',
  },
  {
    id: '10',
    titulo: '10 · Passo 2: acesso recusado',
    tela: 'agente',
    acesso: 'recusado',
  },
  {
    id: '11',
    titulo: '11 · Passo 2: login só cota',
    tela: 'agente',
    acesso: 'so_cota',
  },
  {
    id: '12',
    titulo: '12 · Passo 3: escolher o canal',
    tela: 'agente',
    gaveta: 'onde',
  },
  {
    id: '13',
    titulo: '13 · Bia atendendo',
    tela: 'agente',
    ligada: true,
    pagina: 'atendendo',
  },
  { id: '14', titulo: '14 · Página da Bia', tela: 'agente', ligada: true },
  {
    id: '15',
    titulo: '15 · Alterar a corretora',
    tela: 'agente',
    ligada: true,
    gaveta: 'corretora',
  },
  {
    id: '16',
    titulo: '16 · Acesso recusado meses depois',
    tela: 'agente',
    ligada: true,
    pagina: 'recusado',
  },
];

const CAMPO =
  'w-full px-3 text-base rounded-xl min-h-11 !bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12 disabled:opacity-60';
const anel = erro => (erro ? 'ring-2 ring-n-ruby-9' : 'ring-n-slate-7');
const comAcessoConferido = acesso => ['ok', 'so_cota'].includes(acesso);
const comCampos = acesso =>
  ['vazio', 'faltando', 'conferindo', 'indisponivel', 'recusado'].includes(
    acesso
  );
const soCotaNoItem = (variante, indice) =>
  variante.acesso === 'so_cota' && indice === FAZ.length - 1;
// Com texto digitado, Esc e o clique fora não fecham a gaveta (o X continua fechando).
const naoPerderOQueDigitou = () => false;
</script>

<template>
  <Story
    title="Agentes/Seguro Viagem Universal (contratado)"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant
      v-for="variante in VARIANTES"
      :key="variante.id"
      :title="variante.titulo"
    >
      <div
        :data-variante="variante.id"
        class="w-full min-h-screen bg-n-background"
      >
        <!-- 01 · Criar agente numa conta de seguros: "Vendem sozinhos" antes dos ramos -->
        <div
          v-if="variante.tela === 'area'"
          class="flex flex-col w-full max-w-5xl gap-8 px-4 py-6 mx-auto md:px-6"
        >
          <button
            type="button"
            class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11"
          >
            <span
              class="i-lucide-arrow-left size-4 rtl:rotate-180"
              aria-hidden="true"
            />
            {{ t('AGENTS.JORNADA.CRIAR.VOLTAR') }}
          </button>
          <AgentesHeroi
            :titulo="t('AGENTS.JORNADA.ESCOLHER.TITULO')"
            :texto="t('AGENTS.JORNADA.RAMOS.TEXTO_DA_PAGINA')"
          >
            <section
              data-vendem-sozinhos
              aria-labelledby="vendem-sozinhos-titulo"
              class="flex flex-col gap-4"
            >
              <div class="flex flex-col max-w-2xl gap-1">
                <h2
                  id="vendem-sozinhos-titulo"
                  class="m-0 text-xl font-semibold text-white"
                >
                  Vendem sozinhos
                </h2>
                <p class="m-0 text-base leading-relaxed text-white/80">
                  Cotam, fazem a proposta e mandam o link de pagamento. Você só
                  informa os dados da sua corretora.
                </p>
              </div>
              <ul class="p-0 m-0 list-none">
                <li
                  class="relative flex flex-col gap-4 p-5 transition shadow-sm md:flex-row md:items-center rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:ring-n-blue-11 hover:shadow-md"
                >
                  <div class="flex items-start gap-3 grow">
                    <span
                      aria-hidden="true"
                      class="grid rounded-xl place-items-center size-12 shrink-0"
                      :class="TOM_DO_RAMO.azul"
                    >
                      <span class="i-lucide-plane size-6" />
                    </span>
                    <div class="flex flex-col min-w-0 gap-1">
                      <h3
                        class="m-0 text-lg font-semibold leading-snug text-n-slate-12"
                      >
                        Seguro Viagem Universal
                      </h3>
                      <p class="m-0 text-sm leading-relaxed text-n-slate-11">
                        Vende o seguro viagem da Universal do começo ao fim:
                        cota, faz a proposta e manda o link de pagamento.
                      </p>
                      <p
                        class="flex items-center gap-1.5 m-0 text-sm text-n-slate-12"
                      >
                        <span
                          class="i-lucide-key-round size-4 shrink-0 text-n-slate-11"
                          aria-hidden="true"
                        />
                        Precisa do login do portal da Universal.
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    aria-label="Ver como funciona: Seguro Viagem Universal"
                    class="inline-flex items-center justify-between w-full gap-3 px-4 text-base font-semibold transition md:w-auto shrink-0 min-h-12 rounded-xl bg-n-blue-2 text-n-blue-11 after:absolute after:inset-0 after:rounded-2xl"
                  >
                    Ver como funciona
                    <span
                      class="i-lucide-arrow-right size-5 shrink-0 rtl:rotate-180"
                      aria-hidden="true"
                    />
                  </button>
                </li>
              </ul>
            </section>
            <div class="pt-6 border-t border-white/15">
              <RamosProntos :ramos="MODELOS_DE_RAMO" pode-usar />
            </div>
            <ul
              :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
              class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
            >
              <ModeloCartao
                v-for="modelo in MODELOS"
                :key="modelo.chave"
                :modelo="modelo"
                pode-usar
              />
            </ul>
            <p class="pt-5 m-0 border-t border-white/15">
              <button
                type="button"
                class="px-0 text-base font-semibold text-white underline text-start min-h-11"
              >
                {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO') }}
              </button>
            </p>
          </AgentesHeroi>
          <section
            aria-labelledby="outro-tipo-titulo"
            class="flex flex-col gap-3"
          >
            <div class="flex flex-col gap-1">
              <h2
                id="outro-tipo-titulo"
                class="m-0 text-base font-semibold text-n-slate-12"
              >
                {{ t('AGENTS.JORNADA.ESCOLHER.OUTRO_TIPO') }}
              </h2>
              <p class="m-0 text-sm text-n-slate-11">
                {{ t('AGENTS.JORNADA.ESCOLHER.OUTRO_TEXTO') }}
              </p>
            </div>
            <ul class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2">
              <li>
                <button
                  type="button"
                  class="flex items-start w-full h-full gap-3 p-4 transition text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-8 hover:shadow-sm min-h-11"
                >
                  <span
                    aria-hidden="true"
                    class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
                  >
                    <span class="i-lucide-users size-5" />
                  </span>
                  <span class="flex flex-col gap-0.5 grow min-w-0">
                    <span class="text-sm font-semibold text-n-slate-12">
                      {{ t('AGENTS.JORNADA.MODELOS.COPILOTO') }}
                    </span>
                    <span class="text-sm text-n-slate-11">
                      {{ t('AGENTS.JORNADA.MODELOS.COPILOTO_TEXTO') }}
                    </span>
                  </span>
                  <span
                    class="self-center i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
                    aria-hidden="true"
                  />
                </button>
              </li>
            </ul>
          </section>
        </div>

        <!-- 02 a 04 · Página do modelo (e o passo 1 por cima) -->
        <div
          v-else-if="variante.tela === 'modelo'"
          class="flex flex-col w-full max-w-5xl gap-8 px-4 py-6 mx-auto md:px-6"
        >
          <button
            type="button"
            class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11"
          >
            <span
              class="i-lucide-arrow-left size-4 rtl:rotate-180"
              aria-hidden="true"
            />
            Voltar para Criar agente
          </button>
          <AgentesHeroi
            titulo="Seguro Viagem Universal"
            texto="Um agente que vende seguro viagem da Universal para quem vai viajar, do primeiro oi ao link de pagamento."
          >
            <template #acoes>
              <AgenteBotao
                data-contratar
                variante="branco"
                tamanho="xl"
                class="w-full md:w-auto"
              >
                Contratar
              </AgenteBotao>
            </template>
          </AgentesHeroi>
          <div
            class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]"
          >
            <div class="flex flex-col gap-6">
              <section
                class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak md:p-6"
              >
                <h2 class="m-0 text-lg font-semibold text-n-slate-12">
                  O que ele faz
                </h2>
                <ul class="flex flex-col gap-3 p-0 m-0 list-none">
                  <li
                    v-for="item in FAZ"
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
                  O que você vai precisar
                </h2>
                <ol class="flex flex-col gap-3 p-0 m-0 list-none">
                  <li
                    v-for="(item, indice) in PRECISA"
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
                  Você não escreve nada: o jeito de atender já vem pronto e
                  melhora sozinho.
                </p>
              </section>
            </div>
            <section class="flex flex-col gap-3">
              <h2 class="m-0 text-lg font-semibold text-n-slate-12">
                Exemplo de conversa
              </h2>
              <CelularConversa
                :mensagens="CONVERSA"
                :nome="NOME"
                :estado="CORRETORA"
                rotulo-sr="Exemplo de conversa, não é um agente de verdade"
              />
            </section>
          </div>
          <AgenteBotao tamanho="xl" bloco class="md:hidden">
            Contratar
          </AgenteBotao>

          <AgenteGaveta
            v-if="variante.dados"
            titulo="Contratar o agente"
            :pode-fechar="naoPerderOQueDigitou"
          >
            <div class="flex flex-col gap-5">
              <p class="m-0 text-base font-semibold text-n-blue-11">
                Passo 1 de 3: sobre a sua corretora.
              </p>
              <div class="flex flex-col gap-1">
                <label
                  for="contratar-nome"
                  class="text-sm font-medium text-n-slate-12"
                >
                  Nome do agente
                </label>
                <input
                  id="contratar-nome"
                  :value="NOME"
                  maxlength="120"
                  autocomplete="off"
                  :class="[CAMPO, anel(false)]"
                />
                <p class="m-0 text-sm text-n-slate-11">
                  É o nome que o viajante vê na conversa.
                </p>
              </div>
              <div class="flex flex-col gap-1">
                <label
                  for="contratar-corretora"
                  class="text-sm font-medium text-n-slate-12"
                >
                  Nome da corretora
                </label>
                <input
                  id="contratar-corretora"
                  :value="variante.dados === 'erro' ? '' : CORRETORA"
                  maxlength="120"
                  autocomplete="off"
                  :aria-invalid="variante.dados === 'erro' ? 'true' : undefined"
                  :aria-describedby="
                    variante.dados === 'erro'
                      ? 'contratar-corretora-erro'
                      : undefined
                  "
                  :class="[CAMPO, anel(variante.dados === 'erro')]"
                />
                <p
                  v-if="variante.dados === 'erro'"
                  id="contratar-corretora-erro"
                  role="alert"
                  class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
                >
                  <span
                    class="i-lucide-circle-alert size-4 shrink-0"
                    aria-hidden="true"
                  />
                  Escreva o nome da corretora.
                </p>
              </div>
              <div class="flex flex-col gap-1">
                <label
                  for="contratar-sobre"
                  class="text-sm font-medium text-n-slate-12"
                >
                  Sobre a corretora (pode deixar para depois)
                </label>
                <textarea
                  id="contratar-sobre"
                  rows="4"
                  maxlength="1000"
                  placeholder="Ex.: Corretora em Campinas desde 2010. Atendemos famílias e empresas."
                  class="py-2 min-h-32 resize-y"
                  :class="[CAMPO, anel(false)]"
                />
                <p class="m-0 text-sm text-n-slate-11">
                  O agente usa para se apresentar.
                </p>
              </div>
            </div>
            <template #rodape>
              <AgenteBotao data-contratar-enviar tamanho="xl" bloco>
                Contratar
              </AgenteBotao>
            </template>
          </AgenteGaveta>
        </div>

        <!-- 05 a 16 · Página da Bia: o acesso, o canal e o dia a dia -->
        <div
          v-else
          class="flex flex-col w-full max-w-5xl gap-6 px-4 py-6 mx-auto md:px-6"
        >
          <!-- Até ter acesso e canal, "Falta terminar" no lugar do interruptor. -->
          <PaginaHeroi
            :nome="NOME"
            :estado="variante.ligada ? ESTADO.ATENDENDO : ESTADO.FALTA_TERMINAR"
            :onde="
              variante.ligada
                ? t('AGENTS.JORNADA.PAGINA.RESPONDE_NO', {
                    canal: CANAL,
                    quando: 'Sempre',
                  })
                : t('AGENTS.JORNADA.PAGINA.NENHUM_CANAL')
            "
            href-lista="#"
            :pode-gerenciar="!!variante.ligada"
          />
          <p
            v-if="variante.pagina === 'atendendo'"
            role="status"
            class="flex items-start gap-3 p-4 m-0 text-base rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6 text-n-slate-12"
          >
            <span
              class="i-lucide-circle-check mt-0.5 size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            Bia está atendendo no {{ CANAL }}.
          </p>
          <AgenteErro
            v-if="variante.pagina === 'recusado'"
            titulo="A Universal recusou o acesso da Bia."
            garantia="Enquanto isso, quem quiser cotar passa para a sua equipe."
            acao="Alterar"
            icone-acao="i-lucide-key-round"
          />

          <section
            v-if="variante.ligada"
            data-corretora-e-acesso
            aria-labelledby="corretora-e-acesso-titulo"
            class="flex flex-col gap-1 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <h2
              id="corretora-e-acesso-titulo"
              class="m-0 text-lg font-semibold text-n-slate-12"
            >
              Corretora e acesso
            </h2>
            <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
              <li class="flex items-center justify-between gap-3 py-3">
                <span class="flex flex-col min-w-0 gap-0.5">
                  <span class="text-sm text-n-slate-11">Corretora</span>
                  <span class="text-base font-medium truncate text-n-slate-12">
                    {{ CORRETORA }}
                  </span>
                </span>
                <AgenteBotao
                  variante="contorno"
                  aria-label="Alterar a corretora"
                >
                  Alterar
                </AgenteBotao>
              </li>
              <li class="flex items-center justify-between gap-3 py-3">
                <span class="flex flex-col min-w-0 gap-0.5">
                  <span class="text-sm text-n-slate-11">
                    Portal da Universal
                  </span>
                  <span
                    v-if="variante.pagina === 'recusado'"
                    class="flex items-center gap-1.5 text-base font-medium text-n-ruby-11"
                  >
                    <span
                      class="i-lucide-circle-alert size-4 shrink-0"
                      aria-hidden="true"
                    />
                    Recusado
                  </span>
                  <span
                    v-else
                    class="flex items-center gap-1.5 text-base font-medium text-n-slate-12"
                  >
                    <span
                      class="i-lucide-circle-check size-4 shrink-0 text-n-teal-11"
                      aria-hidden="true"
                    />
                    Conferido
                  </span>
                </span>
                <AgenteBotao
                  variante="contorno"
                  aria-label="Alterar o acesso ao portal da Universal"
                >
                  Alterar
                </AgenteBotao>
              </li>
            </ul>
          </section>

          <section
            class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <h2 class="m-0 text-lg font-semibold text-n-slate-12">
              O que Bia faz
            </h2>
            <ul class="flex flex-col gap-3 p-0 m-0 list-none">
              <li
                v-for="(item, indice) in FAZ"
                :key="item"
                class="flex items-start gap-3 text-base text-n-slate-12"
              >
                <span
                  v-if="soCotaNoItem(variante, indice)"
                  class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
                  aria-hidden="true"
                />
                <span
                  v-else
                  class="i-lucide-circle-check mt-0.5 size-5 shrink-0 text-n-teal-11"
                  aria-hidden="true"
                />
                <span class="flex flex-col gap-0.5">
                  {{ item }}
                  <span
                    v-if="soCotaNoItem(variante, indice)"
                    class="text-sm text-n-slate-11"
                  >
                    Precisa de um login que faz proposta.
                  </span>
                </span>
              </li>
            </ul>
          </section>

          <!-- Passo 3: a escolha de canal de sempre, com a única caixa livre já marcada. -->
          <AgenteGaveta
            v-if="variante.gaveta === 'onde'"
            :titulo="t('AGENTS.JORNADA.ONDE_QUANDO.TITULO', { nome: NOME })"
          >
            <div class="flex flex-col gap-5">
              <p class="m-0 text-base font-semibold text-n-blue-11">
                Passo 3 de 3: onde a Bia atende.
              </p>
              <OndeQuandoEscolha
                :onde="11"
                quando="always"
                :canais="CANAIS"
                :agente-id="77"
                :nome="NOME"
                :horarios="HORARIOS"
              />
            </div>
            <template #rodape>
              <AgenteBotao tamanho="xl" bloco>
                {{ t('AGENTS.JORNADA.PAGINA.ONDE.COMECAR') }}
              </AgenteBotao>
              <p class="m-0 text-sm text-center text-n-slate-11">
                {{
                  t('AGENTS.JORNADA.PAGINA.ONDE.VOLTAR_TEXTO', { nome: NOME })
                }}
              </p>
            </template>
          </AgenteGaveta>

          <!-- Alterar a corretora: só os dois campos dela; o nome da Bia fica na gaveta de foto e nome. -->
          <AgenteGaveta
            v-else-if="variante.gaveta === 'corretora'"
            titulo="Corretora"
          >
            <div class="flex flex-col gap-5">
              <div class="flex flex-col gap-1">
                <label
                  for="corretora-nome"
                  class="text-sm font-medium text-n-slate-12"
                >
                  Nome da corretora
                </label>
                <input
                  id="corretora-nome"
                  :value="CORRETORA"
                  maxlength="120"
                  autocomplete="off"
                  :class="[CAMPO, anel(false)]"
                />
              </div>
              <div class="flex flex-col gap-1">
                <label
                  for="corretora-sobre"
                  class="text-sm font-medium text-n-slate-12"
                >
                  Sobre a corretora
                </label>
                <textarea
                  id="corretora-sobre"
                  :value="SOBRE"
                  rows="4"
                  maxlength="1000"
                  class="py-2 min-h-32 resize-y"
                  :class="[CAMPO, anel(false)]"
                />
                <p class="m-0 text-sm text-n-slate-11">
                  A Bia usa para se apresentar.
                </p>
              </div>
            </div>
            <template #rodape>
              <div class="flex flex-wrap justify-end gap-2">
                <AgenteBotao variante="contorno" tamanho="lg">
                  Cancelar
                </AgenteBotao>
                <AgenteBotao tamanho="lg">Salvar</AgenteBotao>
              </div>
            </template>
          </AgenteGaveta>

          <!-- Passo 2: o acesso ao portal da Universal. -->
          <AgenteGaveta
            v-else-if="variante.acesso"
            titulo="Acesso ao portal da Universal"
          >
            <div class="flex flex-col gap-5">
              <p
                v-if="['vazio', 'faltando'].includes(variante.acesso)"
                role="status"
                class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6 text-n-slate-12"
              >
                <span
                  class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
                  aria-hidden="true"
                />
                Pronto, a Bia foi criada. Ela começa parada. Falta o acesso à
                Universal e o canal.
              </p>

              <!-- Conferido: só o resultado e o login mascarado; a senha nunca volta para a tela. -->
              <template v-if="comAcessoConferido(variante.acesso)">
                <div
                  v-if="variante.acesso === 'ok'"
                  role="status"
                  class="flex items-start gap-3 p-4 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
                >
                  <span
                    class="i-lucide-circle-check size-6 shrink-0 text-n-teal-11"
                    aria-hidden="true"
                  />
                  <div class="flex flex-col gap-1">
                    <p class="m-0 text-base font-semibold text-n-slate-12">
                      Acesso conferido
                    </p>
                    <p class="m-0 text-sm text-n-slate-12">
                      Bia já pode cotar e mandar o link de pagamento.
                    </p>
                  </div>
                </div>
                <div
                  v-else
                  role="status"
                  class="flex items-start gap-3 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
                >
                  <span
                    class="i-lucide-triangle-alert size-6 shrink-0 text-n-amber-11"
                    aria-hidden="true"
                  />
                  <div class="flex flex-col gap-1">
                    <p class="m-0 text-base font-semibold text-n-slate-12">
                      Esse login só faz cotação
                    </p>
                    <p class="m-0 text-sm text-n-slate-12">
                      Bia cota e tira dúvidas. Quando o cliente quiser fechar,
                      ela passa a conversa para a sua equipe. Para a Bia fazer a
                      proposta sozinha, peça à Universal para liberar a emissão
                      nesse login.
                    </p>
                  </div>
                </div>
                <div
                  class="flex items-center justify-between gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
                >
                  <div class="flex flex-col min-w-0 gap-0.5">
                    <span class="text-sm text-n-slate-11">Login do portal</span>
                    <span
                      class="text-base font-medium truncate text-n-slate-12"
                    >
                      corr•••••••plo
                    </span>
                    <span class="text-sm text-n-slate-11">
                      Senha guardada com segurança
                    </span>
                  </div>
                  <AgenteBotao
                    variante="contorno"
                    aria-label="Alterar o login e a senha"
                  >
                    Alterar
                  </AgenteBotao>
                </div>
              </template>

              <template v-if="comCampos(variante.acesso)">
                <p class="m-0 text-base font-semibold text-n-blue-11">
                  Passo 2 de 3: acesso à Universal.
                </p>
                <AgenteErro
                  v-if="variante.acesso === 'recusado'"
                  titulo="A Universal não aceitou esse login e senha."
                  garantia="Confira os dois e digite de novo. Nada foi guardado."
                />
                <AgenteErro
                  v-else-if="variante.acesso === 'indisponivel'"
                  titulo="A Universal não respondeu agora."
                  garantia="Nada foi guardado. Tente de novo em alguns minutos."
                />
                <p v-else class="m-0 text-base text-n-slate-12">
                  Bia entra no portal da Universal com o login da sua corretora
                  para cotar e fazer a proposta.
                </p>
                <div class="flex flex-col gap-1">
                  <label
                    for="acesso-login"
                    class="text-sm font-medium text-n-slate-12"
                  >
                    Login do portal
                  </label>
                  <input
                    id="acesso-login"
                    :value="
                      ['vazio', 'faltando'].includes(variante.acesso)
                        ? ''
                        : 'corretora.exemplo'
                    "
                    autocomplete="off"
                    autocapitalize="none"
                    autocorrect="off"
                    spellcheck="false"
                    :disabled="variante.acesso === 'conferindo'"
                    :aria-invalid="
                      variante.acesso === 'faltando' ? 'true' : undefined
                    "
                    :class="[CAMPO, anel(variante.acesso === 'faltando')]"
                  />
                  <p
                    v-if="variante.acesso === 'faltando'"
                    role="alert"
                    class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
                  >
                    <span
                      class="i-lucide-circle-alert size-4 shrink-0"
                      aria-hidden="true"
                    />
                    Escreva o login do portal.
                  </p>
                  <p class="m-0 text-sm text-n-slate-11">
                    É o mesmo login do site da Universal. Não tem? Peça ao seu
                    contato comercial na Universal.
                  </p>
                </div>
                <div class="flex flex-col gap-1">
                  <label
                    for="acesso-senha"
                    class="text-sm font-medium text-n-slate-12"
                  >
                    Senha do portal
                  </label>
                  <div class="relative">
                    <input
                      id="acesso-senha"
                      type="password"
                      :value="
                        variante.acesso === 'conferindo' ? 'exemplo123' : ''
                      "
                      autocomplete="off"
                      class="pe-12"
                      :disabled="variante.acesso === 'conferindo'"
                      :aria-invalid="
                        ['faltando', 'recusado'].includes(variante.acesso)
                          ? 'true'
                          : undefined
                      "
                      :class="[
                        CAMPO,
                        anel(
                          ['faltando', 'recusado'].includes(variante.acesso)
                        ),
                      ]"
                    />
                    <button
                      type="button"
                      aria-label="Mostrar senha"
                      :disabled="variante.acesso === 'conferindo'"
                      class="absolute inset-y-0 grid p-0 end-0 w-11 place-items-center rounded-e-xl text-n-slate-11 hover:text-n-slate-12 disabled:opacity-60"
                    >
                      <span class="i-lucide-eye size-5" aria-hidden="true" />
                    </button>
                  </div>
                  <p
                    v-if="variante.acesso === 'faltando'"
                    role="alert"
                    class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
                  >
                    <span
                      class="i-lucide-circle-alert size-4 shrink-0"
                      aria-hidden="true"
                    />
                    Escreva a senha do portal.
                  </p>
                  <p
                    v-else-if="variante.acesso === 'recusado'"
                    class="m-0 text-sm text-n-slate-11"
                  >
                    Esqueceu a senha? Troque no site da Universal.
                  </p>
                  <p v-else class="m-0 text-sm text-n-slate-11">
                    Depois de conferida, a senha fica guardada e não aparece
                    mais.
                  </p>
                </div>
              </template>
            </div>
            <template #rodape>
              <template v-if="comAcessoConferido(variante.acesso)">
                <AgenteBotao
                  data-escolher-canal
                  tamanho="xl"
                  bloco
                  icone-direita="i-lucide-arrow-right"
                >
                  Escolher o canal
                </AgenteBotao>
                <p class="m-0 text-sm text-center text-n-slate-11">
                  Último passo: onde Bia atende os viajantes.
                </p>
              </template>
              <AgenteBotao
                v-else
                data-conferir
                tamanho="xl"
                bloco
                :carregando="variante.acesso === 'conferindo'"
                rotulo-carregando="Conferindo com a Universal…"
              >
                Conferir acesso
              </AgenteBotao>
            </template>
          </AgenteGaveta>
        </div>
      </div>
    </Variant>
  </Story>
</template>
