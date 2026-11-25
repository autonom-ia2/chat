<script setup>
import { getCurrentInstance } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import CelularConversa from '../components/CelularConversa.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import PaginaHeroi from '../components/pagina/PaginaHeroi.vue';
import GavetaOndeQuando from '../components/pagina/GavetaOndeQuando.vue';
import { MODELOS } from '../constants/modelos';
import { TOM_DO_RAMO } from '../constants/modelosDeRamo';
import { ESTADO } from '../utils/estadoDoAgente';

// #3211 (Tarefa 24) — mockup do agente pronto "Seguro Viagem Universal", para o Rodrigo aprovar a jornada em prints
// antes de qualquer tela de verdade. Monta com os componentes reais da área de Agentes; os textos ficam aqui, soltos,
// porque é só a história. Dados fictícios: a agente "Bia" da "Corretora Exemplo". Nenhum login de verdade.
// Uma variante por estado: 01 a área com "Prontos para contratar"; 02 a página do modelo; 03 e 04 os três campos
// (com erro de campo); 05 a 09 o acesso à Universal (vazio, conferindo, conferido, recusado, só cota); 10 a escolha
// do canal, que é a gaveta "Onde" de sempre.
useI18n().locale.value = 'pt_BR';

// A gaveta "Onde" e o Teleport leem a loja; fora do painel (Histoire), uma loja mínima de mentira.
const globais = getCurrentInstance().appContext.config.globalProperties;
if (!globais.$store) {
  const getters = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 1, accounts: [{ id: 1, role: 'administrator' }] },
    getCurrentCustomRoleId: null,
    'accounts/isRTL': false,
    'accounts/getAccount': () => ({ id: 1, features: {} }),
    'accounts/isFeatureEnabledonAccount': () => false,
    'globalConfig/get': { installationName: 'Hub2You' },
  };
  globais.$store = { getters, dispatch: () => Promise.resolve() };
}

const NOME = 'Bia';
const CORRETORA = 'Corretora Exemplo';
const SOBRE =
  'Corretora de seguros em Campinas desde 2010. Atendemos famílias e empresas, com seguro viagem para o mundo todo.';

const FAZ = [
  'Tira as dúvidas do viajante com as regras oficiais da Universal',
  'Cota na hora, com o destino, as datas e a idade de cada um',
  'Ajuda a escolher o plano e explica o que cada um cobre',
  'Monta a proposta e manda o link de pagamento',
];

const PRECISA = [
  'O nome da sua corretora e uma frase sobre ela',
  'O login e a senha do portal da Universal',
  'Um canal para atender, como o WhatsApp',
];

const CONVERSA = [
  {
    de: 'cliente',
    texto: 'Oi! Quero seguro para Portugal, de 10 a 24 de janeiro. Somos 2.',
    hora: '19:20',
  },
  {
    de: 'agente',
    texto:
      'Oi! Eu sou a Bia, da Corretora Exemplo. Para vocês dois, o plano mais escolhido para a Europa sai R$ 189,90 por pessoa.',
    hora: '19:21',
  },
  { de: 'cliente', texto: 'Pode ser esse', hora: '19:22' },
  {
    de: 'agente',
    texto:
      'Combinado! Fiz a proposta. Este é o link para pagar: pagamento.exemplo.com.br/a1b2',
    hora: '19:24',
  },
];

const CANAIS = [
  {
    inbox_id: 11,
    name: 'WhatsApp Vendas',
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
  {
    inbox_id: 13,
    name: 'Site da corretora',
    channel_type: 'Channel::WebWidget',
    occupied_by: null,
  },
];

const AGENTE = {
  id: 77,
  name: NOME,
  config: { response_window: 'always' },
  tem_onde_trabalhar: false,
  channels_count: 0,
};

// tela: area | modelo | agente. dados: sem erro, com erro. acesso: vazio | conferindo | ok | recusado | so_cota.
const VARIANTES = [
  {
    id: '01',
    titulo: '01 · Área de Agentes: Prontos para contratar',
    tela: 'area',
  },
  { id: '02', titulo: '02 · Página do modelo', tela: 'modelo' },
  { id: '03', titulo: '03 · Os três campos', tela: 'modelo', dados: 'ok' },
  {
    id: '04',
    titulo: '04 · Os três campos com erro',
    tela: 'modelo',
    dados: 'erro',
  },
  {
    id: '05',
    titulo: '05 · Acesso à Universal: vazio',
    tela: 'agente',
    acesso: 'vazio',
  },
  {
    id: '06',
    titulo: '06 · Acesso à Universal: conferindo',
    tela: 'agente',
    acesso: 'conferindo',
  },
  {
    id: '07',
    titulo: '07 · Acesso à Universal: conferido',
    tela: 'agente',
    acesso: 'ok',
  },
  {
    id: '08',
    titulo: '08 · Acesso à Universal: recusado',
    tela: 'agente',
    acesso: 'recusado',
  },
  {
    id: '09',
    titulo: '09 · Acesso à Universal: só cota',
    tela: 'agente',
    acesso: 'so_cota',
  },
  {
    id: '10',
    titulo: '10 · Escolher o canal (gaveta Onde)',
    tela: 'agente',
    acesso: 'onde',
  },
];

const CAMPO =
  'w-full px-3 text-base rounded-xl min-h-11 !bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12 disabled:opacity-60';
const anel = erro => (erro ? 'ring-2 ring-n-ruby-9' : 'ring-n-slate-7');
const comAcessoConferido = acesso => ['ok', 'so_cota'].includes(acesso);
const comCampos = acesso =>
  ['vazio', 'conferindo', 'recusado'].includes(acesso);
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
        <!-- 01 · Criar agente, com a seção nova antes dos modelos gerais -->
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
            Voltar para Agentes
          </button>
          <AgentesHeroi
            titulo="Criar agente"
            texto="Escolha um modelo pronto. Depois você conta do seu jeito e escolhe o canal no fim."
          >
            <section
              data-prontos-para-contratar
              aria-labelledby="prontos-titulo"
              class="flex flex-col gap-4"
            >
              <div class="flex flex-col max-w-2xl gap-1">
                <h2
                  id="prontos-titulo"
                  class="m-0 text-xl font-semibold text-white"
                >
                  Prontos para contratar
                </h2>
                <p class="m-0 text-base leading-relaxed text-white/80">
                  Agentes completos, que já vendem sozinhos. Você só informa os
                  dados da sua corretora.
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
                    </div>
                  </div>
                  <button
                    type="button"
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
              <h2
                class="pt-6 m-0 text-xl font-semibold text-white border-t border-white/15"
              >
                Ou escolha pelo tipo de trabalho
              </h2>
            </section>
            <ul class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3">
              <ModeloCartao
                v-for="modelo in MODELOS"
                :key="modelo.chave"
                :modelo="modelo"
                pode-usar
              />
            </ul>
          </AgentesHeroi>
        </div>

        <!-- 02 a 04 · Página do modelo (e os três campos por cima) -->
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
                    :key="item"
                    class="flex items-start gap-3 text-base text-n-slate-12"
                  >
                    <span
                      aria-hidden="true"
                      class="grid text-sm font-semibold rounded-full place-items-center size-6 shrink-0 bg-n-blue-3 text-n-blue-11"
                    >
                      {{ indice + 1 }}
                    </span>
                    {{ item }}
                  </li>
                </ol>
                <p
                  class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-slate-2 text-n-slate-12"
                >
                  <span
                    class="i-lucide-sparkles mt-0.5 size-4 shrink-0 text-n-slate-11"
                    aria-hidden="true"
                  />
                  A Hub2You cuida das instruções: você não escreve nada, e cada
                  melhoria chega sozinha.
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
                estado="Corretora Exemplo"
                rotulo-sr="Exemplo de conversa, não é um agente de verdade"
              />
            </section>
          </div>

          <AgenteGaveta v-if="variante.dados" titulo="Contratar o agente">
            <div class="flex flex-col gap-5">
              <p class="m-0 text-base text-n-slate-12">
                Só três respostas. O resto já vem pronto.
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
                  Sobre a corretora
                </label>
                <textarea
                  id="contratar-sobre"
                  :value="SOBRE"
                  rows="4"
                  maxlength="1000"
                  class="py-2 min-h-32 resize-y"
                  :class="[CAMPO, anel(false)]"
                />
                <div class="flex justify-between gap-3">
                  <p class="m-0 text-sm text-n-slate-11">
                    Uma ou duas frases. O agente usa para se apresentar.
                  </p>
                  <span class="text-sm text-n-slate-11 shrink-0">
                    {{ SOBRE.length }} de 1000
                  </span>
                </div>
              </div>
            </div>
            <template #rodape>
              <div class="flex flex-wrap justify-end gap-2">
                <AgenteBotao variante="contorno" tamanho="lg">
                  Cancelar
                </AgenteBotao>
                <AgenteBotao data-contratar-enviar tamanho="lg">
                  Contratar
                </AgenteBotao>
              </div>
            </template>
          </AgenteGaveta>
        </div>

        <!-- 05 a 10 · Página da Bia, recém-contratada, com a gaveta do acesso ou a do canal -->
        <div
          v-else
          class="flex flex-col w-full max-w-5xl gap-6 px-4 py-6 mx-auto md:px-6"
        >
          <PaginaHeroi
            :nome="NOME"
            :estado="ESTADO.PARADO"
            onde="Ainda não está em nenhum canal."
            href-lista="#"
            pode-gerenciar
          />
          <section
            class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <h2 class="m-0 text-lg font-semibold text-n-slate-12">
              O que Bia faz
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

          <GavetaOndeQuando
            v-if="variante.acesso === 'onde'"
            :agente="AGENTE"
            :nome="NOME"
            modo="voltar"
            :canais="CANAIS"
            :horarios="{ 11: 'seg. a sex., 9h às 18h', 12: null, 13: null }"
          />

          <AgenteGaveta v-else titulo="Acesso ao portal da Universal">
            <div class="flex flex-col gap-5">
              <!-- Conferido: só o resultado e o login mascarado; a senha nunca volta para a tela. -->
              <template v-if="comAcessoConferido(variante.acesso)">
                <div
                  v-if="variante.acesso === 'ok'"
                  data-acesso-ok
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
                  data-acesso-so-cota
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
                      Bia cota, mas não faz a proposta nem manda o link de
                      pagamento. Para vender até o fim, peça à Universal um
                      login que faz proposta.
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
                  <AgenteBotao variante="contorno">Alterar</AgenteBotao>
                </div>
              </template>

              <template v-if="comCampos(variante.acesso)">
                <AgenteErro
                  v-if="variante.acesso === 'recusado'"
                  titulo="A Universal não aceitou esse login e senha."
                  garantia="Confira no portal da Universal e digite de novo. Nada foi guardado."
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
                      variante.acesso === 'vazio' ? '' : 'corretora.exemplo'
                    "
                    autocomplete="off"
                    :disabled="variante.acesso === 'conferindo'"
                    :class="[CAMPO, anel(false)]"
                  />
                </div>
                <div class="flex flex-col gap-1">
                  <label
                    for="acesso-senha"
                    class="text-sm font-medium text-n-slate-12"
                  >
                    Senha do portal
                  </label>
                  <input
                    id="acesso-senha"
                    type="password"
                    :value="
                      variante.acesso === 'conferindo' ? 'exemplo123' : ''
                    "
                    autocomplete="off"
                    :disabled="variante.acesso === 'conferindo'"
                    :aria-invalid="
                      variante.acesso === 'recusado' ? 'true' : undefined
                    "
                    :class="[CAMPO, anel(variante.acesso === 'recusado')]"
                  />
                  <p class="m-0 text-sm text-n-slate-11">
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
                :desabilitado="variante.acesso === 'vazio'"
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
