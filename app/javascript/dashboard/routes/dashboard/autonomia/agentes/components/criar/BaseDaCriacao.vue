<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import MaterialLinha from '../pagina/MaterialLinha.vue';
import { MAX_ARQUIVO, MAX_FONTES, enderecoDoSite } from '../../utils/pagina';
import { ocupaVaga } from '../../composables/useConversaDeCriacao';

// #1503 — "Base de conhecimento de {nome}" na etapa Conte da criação (só no Conte): os arquivos e
// sites que o agente lê para responder. A lista é a mesma do clipe da conversa (useConversaDeCriacao
// `base`): o que entra pela conversa aparece aqui, e o que se manda ou tira por aqui vale também lá.
// Cada linha (MaterialLinha) diz o estado em palavras: lendo, pronto ou com problema. Tirar pede
// confirmação dentro da própria linha (sem diálogo do navegador). Quem só vê não tem ação de escrita.
// No computador fica na coluna da direita, abaixo do exemplo; no celular, dentro de uma gaveta
// (`naGaveta`: sem moldura e sem título, que já está no topo da gaveta).
const props = defineProps({
  nome: { type: String, required: true },
  // Materiais da conversa que vão para a base (arquivo ou site), na ordem em que entraram.
  itens: { type: Array, default: () => [] },
  estadoDoMaterial: { type: Function, required: true },
  podeGerenciar: { type: Boolean, default: false },
  erroAoLer: { type: Boolean, default: false },
  naGaveta: { type: Boolean, default: false },
  // O rascunho ainda não tem nome (o Construtor dá o nome no fim): os textos falam "do agente".
  semNome: { type: Boolean, default: false },
  // O servidor não tirou um item ({ nome }): ele voltou para a lista e a caixa avisa.
  falhaAoTirar: { type: Object, default: null },
});

const emit = defineEmits(['anexar', 'site', 'tirar', 'reler']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR.BASE';
const SABE = 'AGENTS.JORNADA.PAGINA.SABE';
const id = `base-${useId()}`;
// Textos com o nome do agente têm a versão "do agente" enquanto ele não tem nome.
const texto = (chave, extra = {}) =>
  props.semNome
    ? t(`${NS}.${chave}_SEM_NOME`, extra)
    : t(`${NS}.${chave}`, { nome: props.nome, ...extra });

const adicionando = ref(false);
const site = ref('');
const erroSite = ref('');
const aviso = ref('');
const confirmando = ref(null);
const anuncio = ref('');
const seletor = ref(null);
const campoSite = ref(null);
const botaoAdicionar = ref(null);
const botaoArquivo = ref(null);
const cancelar = ref(null);
// Elemento de cada linha, para devolver o foco ao "⋯" dela (não reativo: só o foco usa).
const linhas = {};

// O estado da conversa em três palavras: lendo (enviando, na fila ou sendo lido), pronto e problema
// (não deu para ler, ou grande demais e nem foi mandado).
const ESTADO_NA_CAIXA = {
  pronto: 'pronto',
  atencao: 'falha',
  grande: 'falha',
  limite: 'falha',
};
const estadoNaCaixa = material =>
  ESTADO_NA_CAIXA[props.estadoDoMaterial(material)] || 'lendo';

const linhaDe = material => ({
  id: material.id,
  reference: material.nome,
  source_type: material.tipo === 'site' ? 'link' : 'file',
});

const problemaDe = material => {
  const estado = props.estadoDoMaterial(material);
  if (estado === 'grande') return t(`${NS}.GRANDE_TEXTO`);
  if (estado === 'limite') return t(`${SABE}.LIMITE`, { n: MAX_FONTES });
  return '';
};

// Só conta o que ocupa vaga no servidor (grande demais ou que nem subiu fica de fora).
const cheia = computed(
  () => props.itens.filter(ocupaVaga).length >= MAX_FONTES
);

const guardarLinha = material => elemento => {
  linhas[material.id] = elemento?.$el || null;
};

const alternarAdicionar = async () => {
  aviso.value = '';
  adicionando.value = !adicionando.value;
  if (!adicionando.value) return;
  await nextTick();
  botaoArquivo.value?.$el?.focus();
};

const escolherArquivo = () => seletor.value?.click();

// O painel some depois de mandar: o foco volta ao botão que o abriu (não cai no body).
const fecharAdicionar = async () => {
  adicionando.value = false;
  await nextTick();
  botaoAdicionar.value?.$el?.focus();
};

const aoEscolherArquivo = evento => {
  const [arquivo] = evento.target.files || [];
  evento.target.value = '';
  if (!arquivo) return;
  aviso.value = '';
  if (cheia.value) {
    aviso.value = t(`${SABE}.LIMITE`, { n: MAX_FONTES });
    return;
  }
  if (arquivo.size > MAX_ARQUIVO) {
    aviso.value = t(`${SABE}.GRANDE`);
    return;
  }
  emit('anexar', arquivo);
  anuncio.value = t(`${NS}.ENTROU`, { item: arquivo.name });
  fecharAdicionar();
};

const mandarSite = () => {
  const endereco = enderecoDoSite(site.value);
  if (!endereco) {
    erroSite.value = t(`${SABE}.SITE_ERRO`);
    return;
  }
  erroSite.value = '';
  if (cheia.value) {
    aviso.value = t(`${SABE}.LIMITE`, { n: MAX_FONTES });
    return;
  }
  emit('site', endereco);
  anuncio.value = t(`${NS}.ENTROU`, { item: site.value.trim() });
  site.value = '';
  fecharAdicionar();
};

const mandarOutro = async material => {
  if (material.tipo !== 'site') {
    escolherArquivo();
    return;
  }
  adicionando.value = true;
  await nextTick();
  campoSite.value?.focus();
};

// Ref dentro do v-for vem como lista; só uma confirmação fica aberta por vez.
const pedirTirar = async material => {
  confirmando.value = material.id;
  await nextTick();
  [cancelar.value].flat()[0]?.$el?.focus();
};

const desistir = async () => {
  const material = confirmando.value;
  confirmando.value = null;
  await nextTick();
  linhas[material]?.querySelector('[aria-haspopup]')?.focus();
};

const tirar = async material => {
  confirmando.value = null;
  emit('tirar', material);
  anuncio.value = t(`${NS}.TIROU`, { item: material.nome });
  await nextTick();
  botaoAdicionar.value?.$el?.focus();
};

// O item que não saiu voltou para a lista: o leitor de tela ouve isso no lugar do "saiu da base".
watch(
  () => props.falhaAoTirar,
  falha => {
    if (falha) anuncio.value = t(`${NS}.TIRAR_ERRO`, { item: falha.nome });
  }
);

const aoTeclarConfirmacao = evento => {
  if (evento.key !== 'Escape') return;
  evento.preventDefault();
  evento.stopPropagation();
  desistir();
};
</script>

<template>
  <section
    data-base
    :aria-labelledby="naGaveta ? undefined : `${id}-titulo`"
    :aria-label="naGaveta ? texto('TITULO') : undefined"
    class="relative flex flex-col gap-4"
    :class="
      naGaveta
        ? ''
        : 'p-4 rounded-2xl bg-n-solid-1 shadow-sm ring-1 ring-inset ring-n-weak dark:ring-n-slate-6'
    "
  >
    <header class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-library-big size-5" />
      </span>
      <div class="flex flex-col min-w-0 gap-0.5">
        <h2
          v-if="!naGaveta"
          :id="`${id}-titulo`"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ texto('TITULO') }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ texto('TEXTO') }}
        </p>
      </div>
    </header>

    <AgenteErro
      v-if="erroAoLer"
      data-base-erro
      :titulo="t(`${NS}.ERRO_LER`)"
      :garantia="t(`${NS}.ERRO_LER_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="emit('reler')"
    />

    <ul
      v-if="itens.length"
      data-base-lista
      :aria-label="texto('LISTA')"
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <MaterialLinha
        v-for="material in itens"
        :key="material.id"
        :ref="guardarLinha(material)"
        :data-material-id="material.id"
        :fonte="linhaDe(material)"
        :estado="estadoNaCaixa(material)"
        :problema="problemaDe(material)"
        :nome-agente="nome"
        :pode-gerenciar="podeGerenciar"
        :pode-reler="false"
        nome-em-duas-linhas
        @tirar="pedirTirar(material)"
        @mandar-outro="mandarOutro(material)"
      >
        <div
          v-if="confirmando === material.id"
          data-confirmar-tirar
          role="group"
          :aria-labelledby="`${id}-tirar-${material.id}`"
          class="flex flex-col gap-3 p-3 rounded-xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
          @keydown="aoTeclarConfirmacao"
        >
          <div class="flex flex-col gap-0.5">
            <p
              :id="`${id}-tirar-${material.id}`"
              class="m-0 text-sm font-semibold break-all text-n-slate-12"
            >
              {{ t(`${NS}.TIRAR_TITULO`, { item: material.nome }) }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ texto('TIRAR_TEXTO') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <AgenteBotao
              ref="cancelar"
              data-cancelar-tirar
              variante="contorno"
              @click="desistir"
            >
              {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
            </AgenteBotao>
            <AgenteBotao
              data-sim-tirar
              variante="perigo"
              icone="i-lucide-trash-2"
              @click="tirar(material)"
            >
              {{ t(`${NS}.TIRAR`) }}
            </AgenteBotao>
          </div>
        </div>
      </MaterialLinha>
    </ul>
    <div
      v-else-if="!erroAoLer"
      data-base-vazia
      class="flex flex-col items-center gap-2 px-4 py-5 text-center border border-dashed rounded-xl border-n-slate-7 bg-n-slate-2"
    >
      <span
        aria-hidden="true"
        class="flex items-center gap-1.5 text-n-slate-10"
      >
        <span class="i-lucide-file-text size-5" />
        <span class="i-lucide-globe size-5" />
      </span>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.VAZIO`, { nome }) }}
      </p>
    </div>

    <AgenteErro v-if="aviso" data-base-aviso tom="ambar" :titulo="aviso" />
    <AgenteErro
      v-if="falhaAoTirar"
      data-base-falha-tirar
      :titulo="t(`${NS}.TIRAR_ERRO`, { item: falhaAoTirar.nome })"
      :garantia="t(`${NS}.TIRAR_ERRO_GARANTIA`)"
    />

    <div
      v-if="podeGerenciar && adicionando"
      :id="`${id}-adicionar`"
      data-base-adicionar
      class="flex flex-col gap-3 p-3 rounded-xl bg-n-slate-2 ring-1 ring-inset ring-n-weak"
    >
      <AgenteBotao
        ref="botaoArquivo"
        data-base-arquivo
        variante="contorno"
        icone="i-lucide-file-up"
        bloco
        @click="escolherArquivo"
      >
        <span class="flex flex-col py-1 text-start">
          <span>{{ t(`${SABE}.ENVIAR_ARQUIVO`) }}</span>
          <span class="text-xs font-normal text-n-slate-11">
            {{ t(`${SABE}.ENVIAR_ARQUIVO_TEXTO`) }}
          </span>
        </span>
      </AgenteBotao>
      <form class="flex flex-col gap-2" novalidate @submit.prevent="mandarSite">
        <label
          :for="`${id}-site`"
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          <span class="i-lucide-globe size-4" aria-hidden="true" />
          {{ t(`${SABE}.SITE_ROTULO`) }}
        </label>
        <div class="flex gap-2">
          <input
            :id="`${id}-site`"
            ref="campoSite"
            v-model="site"
            data-base-site
            inputmode="url"
            autocomplete="off"
            :placeholder="t(`${NS}.SITE_EXEMPLO`)"
            :aria-invalid="erroSite ? 'true' : undefined"
            :aria-describedby="erroSite ? `${id}-site-erro` : undefined"
            class="flex-1 min-w-0 px-3 text-base border-0 rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 !mb-0 text-n-slate-12"
          />
          <AgenteBotao type="submit" data-base-mandar-site>
            {{ t(`${SABE}.SITE_MANDAR`) }}
          </AgenteBotao>
        </div>
        <p
          v-if="erroSite"
          :id="`${id}-site-erro`"
          data-base-erro-site
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ erroSite }}
        </p>
      </form>
    </div>

    <AgenteBotao
      v-if="podeGerenciar"
      ref="botaoAdicionar"
      data-base-adicionar-botao
      variante="contorno"
      bloco
      :icone="adicionando ? 'i-lucide-x' : 'i-lucide-plus'"
      :aria-expanded="adicionando ? 'true' : 'false'"
      :aria-controls="adicionando ? `${id}-adicionar` : undefined"
      @click="alternarAdicionar"
    >
      {{
        adicionando ? t('AGENTS.JORNADA.COMUM.CANCELAR') : t(`${NS}.ADICIONAR`)
      }}
    </AgenteBotao>
    <input
      v-if="podeGerenciar"
      ref="seletor"
      data-base-seletor
      type="file"
      class="hidden"
      @change="aoEscolherArquivo"
    />
    <p data-base-anuncio class="sr-only" role="status" aria-live="polite">
      {{ anuncio }}
    </p>
  </section>
</template>
