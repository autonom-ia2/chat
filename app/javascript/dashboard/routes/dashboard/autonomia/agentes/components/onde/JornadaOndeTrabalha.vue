<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgenteBotao from '../AgenteBotao.vue';
import GrupoDeCartoes from './GrupoDeCartoes.vue';
import { enderecoDaCaixa } from '../../utils/ondeTrabalha';

// #1366 (protótipo da Fase 2, rodada 2) — "Onde o agente trabalha", uma decisão por tela. Abre no
// começo da criação e no "Mudar" da página do agente.
//   1. Como vai trabalhar: conversa com clientes ou ajuda outros agentes.
//   A2. Em quais canais (só os conectados; mais de um vale).
//   A3. Para cada canal: atende primeiro (a porta, uma por canal) ou recebe quando alguém passar
//       (por atribuição; só existe se o canal já tem quem atenda primeiro).
//   B2. Quem vai ajudar (um ou mais agentes que conversam com clientes).
//   B3. Quando é chamado (frase sugerida, editável).
// Os assuntos (funis) não são escolhidos aqui: ficam no CRM ("Quem cuida do quê?").
const props = defineProps({
  // Sem nome (criação antes da conversa), os textos não citam o agente.
  nome: { type: String, default: '' },
  // Caixas conectadas (store de inboxes).
  caixas: { type: Array, default: () => [] },
  // Quem atende primeiro em cada caixa, sem contar este agente: { [nomeDaCaixa]: nomeDoAgente }.
  portas: { type: Object, default: () => ({}) },
  // Agentes que conversam com clientes (podem ser ajudados).
  principais: { type: Array, default: () => [] },
  inicial: { type: Object, default: null },
  salvando: { type: Boolean, default: false },
  textoFinal: { type: String, default: '' },
  // Na gaveta (página do agente) os cartões do passo 1 ficam um embaixo do outro.
  naGaveta: { type: Boolean, default: false },
});

const emit = defineEmits(['pronto', 'voltar']);

const { t } = useI18n();
const router = useRouter();
const NS = 'AGENTS.JORNADA.ONDE.JORNADA';

const tipo = ref(props.inicial?.tipo || null);
const escolhidas = ref((props.inicial?.caixas || []).map(item => item.caixa));
const papeis = ref(
  Object.fromEntries(
    (props.inicial?.caixas || []).map(item => [item.caixa, item.papel])
  )
);
const assuntosAntes = Object.fromEntries(
  (props.inicial?.caixas || []).map(item => [item.caixa, item.assuntos || []])
);
const ajudados = ref(props.inicial?.ajuda || []);
const quando = ref(props.inicial?.quando || t(`${NS}.QUANDO.SUGESTAO`));
const indice = ref(0);
const titulo = ref(null);

// Só caixas conectadas, na ordem da store; as escolhidas seguem essa ordem.
const caixasEscolhidas = computed(() =>
  props.caixas.filter(caixa => escolhidas.value.includes(caixa.name))
);

const passos = computed(() => {
  if (tipo.value === 'clientes') {
    return [
      'como',
      'canais',
      ...caixasEscolhidas.value.map(caixa => `caixa:${caixa.name}`),
    ];
  }
  if (tipo.value === 'ajuda') return ['como', 'ajudar', 'quando'];
  return ['como'];
});
const passo = computed(() => passos.value[indice.value]);
const caixaDoPasso = computed(() =>
  passo.value?.startsWith('caixa:')
    ? caixasEscolhidas.value.find(
        caixa => `caixa:${caixa.name}` === passo.value
      )
    : null
);
// Último passo: o último canal (caminho A) ou "Quando chamar" (caminho B).
const ultimo = computed(
  () =>
    indice.value === passos.value.length - 1 &&
    (passo.value === 'quando' || passo.value?.startsWith('caixa:'))
);
// Total previsto: antes de escolher, conta o caminho mais curto (3).
const total = computed(() => Math.max(passos.value.length, 3));

const comNome = chave =>
  props.nome
    ? t(`${NS}.${chave}`, { nome: props.nome })
    : t(`${NS}.${chave}_SEM_NOME`);

const opcoesComo = computed(() => [
  {
    valor: 'clientes',
    icone: 'i-lucide-messages-square',
    titulo: t(`${NS}.COMO.CLIENTES.TITULO`),
    texto: t(`${NS}.COMO.CLIENTES.TEXTO`),
  },
  {
    valor: 'ajuda',
    icone: 'i-lucide-users',
    titulo: t(`${NS}.COMO.AJUDA.TITULO`),
    texto: t(`${NS}.COMO.AJUDA.TEXTO`),
  },
]);

const opcoesCanais = computed(() =>
  props.caixas.map(caixa => ({
    valor: caixa.name,
    inbox: caixa,
    titulo: caixa.name,
    texto: enderecoDaCaixa(caixa),
  }))
);

const outro = computed(() =>
  caixaDoPasso.value ? props.portas[caixaDoPasso.value.name] || null : null
);

const opcoesDaCaixa = computed(() => {
  const ocupada = Boolean(outro.value);
  const valores = { outro: outro.value, nome: props.nome };
  return [
    {
      valor: 'primeiro',
      icone: 'i-lucide-door-open',
      titulo: t(`${NS}.CAIXA.PRIMEIRO.TITULO`),
      texto: t(`${NS}.CAIXA.PRIMEIRO.TEXTO`),
      aviso: ocupada
        ? t(`${NS}.CAIXA.PRIMEIRO.OCUPADA`, valores)
        : t(`${NS}.CAIXA.PRIMEIRO.LIVRE`),
    },
    {
      valor: 'recebe',
      icone: 'i-lucide-hand-helping',
      titulo: t(`${NS}.CAIXA.RECEBE.TITULO`),
      texto: comNome('CAIXA.RECEBE.TEXTO'),
      aviso: ocupada ? t(`${NS}.CAIXA.RECEBE.MANTER`, valores) : '',
      desabilitada: !ocupada,
      motivo: t(`${NS}.CAIXA.RECEBE.BLOQUEADO`),
    },
  ];
});

const opcoesAjuda = computed(() =>
  props.principais.map(agente => ({
    valor: agente.name,
    avatar: { nome: agente.name, src: agente.avatar_url },
    titulo: agente.name,
  }))
);

const papelDaCaixa = computed({
  get: () =>
    caixaDoPasso.value ? papeis.value[caixaDoPasso.value.name] : null,
  set: valor => {
    papeis.value = { ...papeis.value, [caixaDoPasso.value.name]: valor };
  },
});

// Canal sem quem atenda primeiro: só "Atende primeiro" é possível, então já vem marcado.
watch(caixaDoPasso, caixa => {
  if (caixa && !props.portas[caixa.name] && !papeis.value[caixa.name]) {
    papeis.value = { ...papeis.value, [caixa.name]: 'primeiro' };
  }
});

const podeSeguir = computed(() => {
  if (passo.value === 'como') return Boolean(tipo.value);
  if (passo.value === 'canais') return escolhidas.value.length > 0;
  if (caixaDoPasso.value) return Boolean(papelDaCaixa.value);
  if (passo.value === 'ajudar') return ajudados.value.length > 0;
  if (passo.value === 'quando') return Boolean(quando.value.trim());
  return false;
});

const montarPapel = () =>
  tipo.value === 'ajuda'
    ? { tipo: 'ajuda', ajuda: ajudados.value, quando: quando.value.trim() }
    : {
        tipo: 'clientes',
        caixas: caixasEscolhidas.value.map(caixa => ({
          caixa: caixa.name,
          papel: papeis.value[caixa.name],
          assuntos: assuntosAntes[caixa.name] || [],
        })),
      };

const focarTitulo = async () => {
  await nextTick();
  titulo.value?.focus();
};

const seguir = () => {
  if (!podeSeguir.value || props.salvando) return;
  if (ultimo.value) {
    emit('pronto', montarPapel());
    return;
  }
  indice.value += 1;
  focarTitulo();
};

const voltar = () => {
  if (indice.value === 0) {
    emit('voltar');
    return;
  }
  indice.value -= 1;
  focarTitulo();
};

const tituloDoPasso = computed(() => {
  if (passo.value === 'como') return comNome('COMO.TITULO');
  if (passo.value === 'canais') return t(`${NS}.CANAIS.TITULO`);
  if (caixaDoPasso.value) {
    return props.nome
      ? t(`${NS}.CAIXA.TITULO`, {
          nome: props.nome,
          canal: caixaDoPasso.value.name,
        })
      : t(`${NS}.CAIXA.TITULO_SEM_NOME`, { canal: caixaDoPasso.value.name });
  }
  if (passo.value === 'ajudar') return comNome('AJUDAR.TITULO');
  return comNome('QUANDO.TITULO');
});

const textoDoPasso = computed(() => {
  if (passo.value === 'como') return t(`${NS}.COMO.TEXTO`);
  if (passo.value === 'canais') return t(`${NS}.CANAIS.TEXTO`);
  if (caixaDoPasso.value) {
    const posicao = caixasEscolhidas.value.indexOf(caixaDoPasso.value) + 1;
    return t(`${NS}.CAIXA.CONTADOR`, {
      i: posicao,
      n: caixasEscolhidas.value.length,
    });
  }
  if (passo.value === 'ajudar') return t(`${NS}.AJUDAR.TEXTO`);
  return t(`${NS}.QUANDO.TEXTO`);
});

const linkConectar = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);
</script>

<template>
  <section
    data-jornada-onde
    :data-passo="passo"
    aria-labelledby="onde-titulo"
    class="flex flex-col gap-6"
  >
    <header class="flex flex-col gap-2">
      <p
        data-progresso
        class="flex items-center gap-2 m-0 text-sm font-medium text-n-slate-11"
      >
        <span aria-hidden="true" class="flex gap-1">
          <span
            v-for="n in total"
            :key="n"
            class="h-1.5 rounded-full transition-all"
            :class="n <= indice + 1 ? 'w-6 bg-n-blue-11' : 'w-3 bg-n-slate-5'"
          />
        </span>
        {{ t(`${NS}.PASSO`, { n: indice + 1, total }) }}
      </p>
      <h2
        id="onde-titulo"
        ref="titulo"
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none md:text-3xl text-n-slate-12"
      >
        {{ tituloDoPasso }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">{{ textoDoPasso }}</p>
    </header>

    <GrupoDeCartoes
      v-if="passo === 'como'"
      v-model="tipo"
      :lado="!naGaveta"
      :rotulo="tituloDoPasso"
      :opcoes="opcoesComo"
    />

    <template v-else-if="passo === 'canais'">
      <GrupoDeCartoes
        v-if="opcoesCanais.length"
        v-model="escolhidas"
        multiplo
        :rotulo="tituloDoPasso"
        :opcoes="opcoesCanais"
      />
      <div
        v-else
        class="flex flex-col gap-2 p-4 text-sm rounded-2xl bg-n-amber-2 text-n-slate-12"
      >
        <p class="m-0">{{ t(`${NS}.CANAIS.VAZIO`) }}</p>
        <a
          :href="linkConectar"
          class="inline-flex items-center font-semibold underline min-h-11 w-fit"
        >
          {{ t(`${NS}.CANAIS.CONECTAR`) }}
        </a>
      </div>
    </template>

    <GrupoDeCartoes
      v-else-if="caixaDoPasso"
      :key="caixaDoPasso.name"
      v-model="papelDaCaixa"
      :rotulo="tituloDoPasso"
      :opcoes="opcoesDaCaixa"
    />

    <template v-else-if="passo === 'ajudar'">
      <GrupoDeCartoes
        v-if="opcoesAjuda.length"
        v-model="ajudados"
        multiplo
        :rotulo="tituloDoPasso"
        :opcoes="opcoesAjuda"
      />
      <p v-else class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.AJUDAR.VAZIO`) }}
      </p>
    </template>

    <label v-else class="flex flex-col gap-2">
      <span class="text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.QUANDO.ROTULO`) }}
      </span>
      <textarea
        v-model="quando"
        data-quando
        rows="3"
        class="w-full px-4 py-3 text-base rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:outline-none focus:ring-2 focus:ring-n-blue-11 !mb-0"
      />
    </label>

    <footer
      class="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <AgenteBotao
        data-voltar-onde
        variante="fantasma"
        icone="i-lucide-arrow-left"
        @click="voltar"
      >
        {{ t(`${NS}.VOLTAR`) }}
      </AgenteBotao>
      <AgenteBotao
        data-seguir-onde
        tamanho="lg"
        class="max-sm:w-full"
        :icone-direita="ultimo ? '' : 'i-lucide-arrow-right'"
        :inativo="!podeSeguir"
        :carregando="salvando"
        @click="seguir"
      >
        {{ ultimo && textoFinal ? textoFinal : t(`${NS}.CONTINUAR`) }}
      </AgenteBotao>
    </footer>
  </section>
</template>
