<script setup>
import { computed, nextTick, onBeforeUnmount, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import MaterialLinha from './MaterialLinha.vue';
import PerguntasParaConferir from './PerguntasParaConferir.vue';
import DialogoAcao from './DialogoAcao.vue';
import {
  MAX_ARQUIVO,
  MAX_FOTO,
  MAX_FONTES,
  enderecoDoSite,
  nomeDaFonte,
} from '../../utils/pagina';
import {
  ESTADO_MATERIAL,
  estadoDoMaterial,
} from '../../utils/estadoDoMaterial';
import { TETO_DA_RELEITURA_MS } from 'dashboard/store/modules/autonomiaSources';

// #1181 PR3 (protótipo T09) — "O que {nome} sabe": o resumo, os arquivos e sites (lendo, pronto ou
// não consegui ler) e, para quem gerencia, mandar arquivo (até 25 MB) ou site, ler de novo, tirar e
// as perguntas de clientes para conferir. Arquivos são sempre opcionais. A lista vem da página, que
// guarda a última lida da store autonomiaSources: a store se relê a cada 4 s enquanto algo está
// sendo lido e zera a lista antes de cada leitura, o que faria a lista sumir e o foco se perder.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  perguntas: { type: Array, default: () => [] },
  fontes: { type: Array, default: () => [] },
  // Só na primeira leitura (as releituras mantêm a lista na tela).
  carregandoFontes: { type: Boolean, default: false },
  erroLer: { type: Boolean, default: false },
  // #1426 — na Fase 2 cada linha mostra o estado real (Lendo → Revisando → Pronto ou Precisa de você). Fora dela, o de
  // hoje.
  fase2: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'perguntaResolvida', 'reler']);

const { t } = useI18n();
const store = useStore();
const flagsDasFontes = useMapGetter('autonomiaSources/getUIFlags');
const NS = 'AGENTS.JORNADA.PAGINA.SABE';
const base = `sabe-${useId()}`;

const adicionando = ref(false);
const site = ref('');
const erroSite = ref('');
const erroArquivo = ref('');
const falhaSalvar = ref(null);
const salvando = ref(false);
const seletor = ref(null);
const substituir = ref(null);
const tirando = ref(null);
const dialogoTirar = ref(null);
const botaoArquivo = ref(null);

const lista = computed(() => props.fontes || []);
const estadoDe = fonte => (props.fase2 ? estadoDoMaterial(fonte) : '');

// #1426 — "Revisando…" parado além do teto da releitura (o worker caiu): a linha libera "Ler de novo". O relógio
// anda a cada 30 s com a gaveta aberta, porque a store já parou de reler.
const RELOGIO_DO_PARADO_MS = 30000;
const relogio = ref(Date.now());
const relogioDoParado = setInterval(() => {
  relogio.value = Date.now();
}, RELOGIO_DO_PARADO_MS);
onBeforeUnmount(() => clearInterval(relogioDoParado));
const paradoRevisando = fonte =>
  estadoDe(fonte) === ESTADO_MATERIAL.REVISANDO &&
  relogio.value - Date.parse(fonte.updated_at || '') > TETO_DA_RELEITURA_MS;

// "Além da conversa, {nome} usa estes arquivos e sites…" só quando há arquivo ou site; sem eles, o
// vazio já diz que sabe só o que foi contado.
const resumo = computed(() => {
  if (props.agente.knowledge_summary) return props.agente.knowledge_summary;
  return lista.value.length ? t(`${NS}.TEXTO`, { nome: props.nome }) : '';
});

const salvar = async acao => {
  salvando.value = true;
  falhaSalvar.value = null;
  try {
    await acao();
    adicionando.value = false;
  } catch (erro) {
    // #1426 — recusa do servidor (422): a mensagem dele vai para a tela, sem "Tentar de novo" (repetir não adianta).
    if (erro?.status === 422) erroArquivo.value = erro.message;
    else falhaSalvar.value = acao;
  } finally {
    salvando.value = false;
  }
};

// #1426 — na Fase 2, imagem vai como foto (lida por OCR e revisada); fora dela, como hoje.
const ehImagem = arquivo => (arquivo?.type || '').startsWith('image/');
const criar = descritor =>
  store.dispatch('autonomiaSources/create', {
    agentId: props.agente.id,
    descriptor: {
      ...descritor,
      kind: 'knowledge',
      ...(props.fase2 && ehImagem(descritor.file)
        ? { sourceType: 'foto' }
        : {}),
    },
  });

const remover = fonte =>
  store.dispatch('autonomiaSources/remove', {
    agentId: props.agente.id,
    sourceId: fonte.id,
  });

const alternarAdicionar = async () => {
  adicionando.value = !adicionando.value;
  if (!adicionando.value) return;
  await nextTick();
  botaoArquivo.value?.$el?.focus();
};

const escolherArquivo = (fonteASubstituir = null) => {
  substituir.value = fonteASubstituir;
  seletor.value?.click();
};

const aoEscolherArquivo = evento => {
  const [arquivo] = evento.target.files || [];
  evento.target.value = '';
  if (!arquivo) return;
  erroArquivo.value = '';
  const trocando = substituir.value;
  if (arquivo.size > MAX_ARQUIVO) {
    erroArquivo.value = t(`${NS}.GRANDE`);
    return;
  }
  if (props.fase2 && ehImagem(arquivo) && arquivo.size > MAX_FOTO) {
    erroArquivo.value = t(`${NS}.FOTO_GRANDE`);
    return;
  }
  if (!trocando && lista.value.length >= MAX_FONTES) {
    erroArquivo.value = t(`${NS}.LIMITE`, { n: MAX_FONTES });
    return;
  }
  // Ao substituir, se o novo entrou e o antigo não saiu, "Tentar de novo" só tira o antigo (criar de
  // novo duplicaria o arquivo e contaria duas vezes no limite).
  let criado = false;
  salvar(async () => {
    if (!criado) {
      await criar({ file: arquivo });
      criado = true;
    }
    if (trocando) await remover(trocando);
  });
};

const mandarSite = () => {
  const url = enderecoDoSite(site.value);
  if (!url) {
    erroSite.value = t(`${NS}.SITE_ERRO`);
    return;
  }
  erroSite.value = '';
  erroArquivo.value = '';
  if (lista.value.length >= MAX_FONTES) {
    erroArquivo.value = t(`${NS}.LIMITE`, { n: MAX_FONTES });
    return;
  }
  salvar(async () => {
    await criar({ url });
    site.value = '';
  });
};

// #1369 — "Ler de novo": a API aceita o pedido (202) e devolve o site como estava ("Pronto" ou
// "Não consegui ler"); a leitura só começa depois, num job. A linha mostra "Lendo…" até o site
// voltar dela: `synced_at` mudou, ou o servidor disse que estava lendo (pending/processing) e saiu
// disso. Enquanto o servidor ainda não começou, a gaveta pede à página que releia a lista a cada
// 4 s (a store só se relê sozinha quando o servidor já diz que está lendo). Depois de 60 s sem
// começar, a linha volta em silêncio ao estado que o servidor mostra e as releituras param.
// { [id da fonte]: { syncedAt, visto (já viu pending/processing), desde } }
const ESTADOS_LENDO = ['pending', 'processing'];
const RELEITURA_MS = 4000;
const LIMITE_RELEITURA_MS = 60000;
const relendo = ref({});
let relogioReleitura = null;

const situacaoDaLeitura = (fonte, marca) => {
  if ((fonte.synced_at ?? null) !== marca.syncedAt) return 'voltou';
  if (ESTADOS_LENDO.includes(fonte.status)) return 'lendo';
  return marca.visto ? 'voltou' : 'esperando';
};

const proximaMarca = (fonte, agora) => {
  const marca = relendo.value[fonte.id];
  if (!marca) return null;
  const situacao = situacaoDaLeitura(fonte, marca);
  if (situacao === 'voltou') return null;
  if (situacao === 'esperando' && agora - marca.desde >= LIMITE_RELEITURA_MS) {
    return null;
  }
  return { ...marca, visto: marca.visto || situacao === 'lendo' };
};

const agendarReleitura = aoReler => {
  clearTimeout(relogioReleitura);
  relogioReleitura = null;
  const esperando = Object.values(relendo.value).some(marca => !marca.visto);
  if (!esperando) return;
  // A página relê a lista (`reler`): ela guarda a última lista lida (sem piscar a gaveta) e mostra
  // o erro se falhar. Com uma leitura ainda em andamento, este intervalo passa sem pedir outra.
  relogioReleitura = setTimeout(() => {
    relogioReleitura = null;
    if (!flagsDasFontes.value?.fetchingList) emit('reler');
    aoReler();
  }, RELEITURA_MS);
};

const acompanharLeitura = () => {
  const agora = Date.now();
  relendo.value = Object.fromEntries(
    lista.value.flatMap(fonte => {
      const marca = proximaMarca(fonte, agora);
      return marca ? [[fonte.id, marca]] : [];
    })
  );
  agendarReleitura(acompanharLeitura);
};

watch(lista, acompanharLeitura);
onBeforeUnmount(() => clearTimeout(relogioReleitura));

const lerDeNovo = fonte =>
  salvar(async () => {
    await store.dispatch('autonomiaSources/resync', {
      agentId: props.agente.id,
      sourceId: fonte.id,
    });
    relendo.value = {
      ...relendo.value,
      [fonte.id]: {
        syncedAt: fonte.synced_at ?? null,
        visto: false,
        desde: Date.now(),
      },
    };
    acompanharLeitura();
  });

const pedirTirar = fonte => {
  tirando.value = fonte;
  dialogoTirar.value?.abrir();
};

const tirar = () => remover(tirando.value);
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`, { nome })" @fechar="emit('fechar')">
    <p v-if="resumo" data-resumo class="m-0 text-sm text-n-slate-11">
      {{ resumo }}
    </p>

    <div
      v-if="podeGerenciar && adicionando"
      data-adicionar
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-slate-2 ring-1 ring-inset ring-n-weak"
    >
      <AgenteBotao
        ref="botaoArquivo"
        data-enviar-arquivo
        variante="contorno"
        icone="i-lucide-file-text"
        bloco
        :carregando="salvando"
        @click="escolherArquivo()"
      >
        <span class="flex flex-col text-start">
          <span>{{ t(`${NS}.ENVIAR_ARQUIVO`) }}</span>
          <span class="text-xs font-normal text-n-slate-11">
            {{ t(`${NS}.ENVIAR_ARQUIVO_TEXTO`) }}
          </span>
        </span>
      </AgenteBotao>
      <form class="flex flex-col gap-2" novalidate @submit.prevent="mandarSite">
        <span
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          <span class="i-lucide-globe size-4" aria-hidden="true" />
          {{ t(`${NS}.SITE`) }}
        </span>
        <label :for="`${base}-site`" class="text-sm text-n-slate-11">
          {{ t(`${NS}.SITE_ROTULO`) }}
        </label>
        <div class="flex gap-2">
          <input
            :id="`${base}-site`"
            v-model="site"
            data-site
            inputmode="url"
            autocomplete="off"
            :aria-invalid="erroSite ? 'true' : undefined"
            :aria-describedby="erroSite ? `${base}-site-erro` : undefined"
            class="flex-1 min-w-0 px-3 text-base rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12"
          />
          <AgenteBotao type="submit" data-mandar-site :carregando="salvando">
            {{ t(`${NS}.SITE_MANDAR`) }}
          </AgenteBotao>
        </div>
        <p
          v-if="erroSite"
          :id="`${base}-site-erro`"
          data-erro-site
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ erroSite }}
        </p>
      </form>
    </div>
    <input
      ref="seletor"
      data-seletor
      type="file"
      class="hidden"
      @change="aoEscolherArquivo"
    />

    <AgenteErro
      v-if="falhaSalvar"
      data-erro-salvar
      :titulo="t(`${NS}.ERRO`)"
      :garantia="t(`${NS}.ERRO_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      :carregando="salvando"
      @acao="salvar(falhaSalvar)"
    />
    <AgenteErro
      v-if="erroArquivo"
      data-erro-arquivo
      tom="ambar"
      :titulo="erroArquivo"
    />

    <AgenteErro
      v-if="erroLer"
      data-erro-ler
      :titulo="t(`${NS}.LER_ERRO`)"
      :garantia="t(`${NS}.ERRO_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="emit('reler')"
    />
    <ul
      v-else-if="lista.length"
      :aria-label="t(`${NS}.LISTA`)"
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <MaterialLinha
        v-for="fonte in lista"
        :key="fonte.id"
        :fonte="fonte"
        :nome-agente="nome"
        :relendo="fonte.id in relendo"
        :estado="estadoDe(fonte)"
        :reler-parado="podeGerenciar && paradoRevisando(fonte)"
        :pode-gerenciar="podeGerenciar"
        @ler-de-novo="lerDeNovo"
        @tirar="pedirTirar"
        @mandar-outro="escolherArquivo"
      />
    </ul>
    <div
      v-else-if="!carregandoFontes"
      data-vazio
      class="flex flex-col items-center gap-2 p-6 text-sm text-center rounded-2xl bg-n-slate-2 text-n-slate-11"
    >
      <span class="i-lucide-book-open size-8" aria-hidden="true" />
      <p class="m-0">{{ t(`${NS}.VAZIO`, { nome }) }}</p>
    </div>

    <PerguntasParaConferir
      v-if="podeGerenciar && perguntas.length"
      :agent-id="agente.id"
      :nome-agente="nome"
      :perguntas="perguntas"
      @resolvida="emit('perguntaResolvida', $event)"
    />

    <template v-if="podeGerenciar" #rodape>
      <AgenteBotao
        data-mandar
        tamanho="lg"
        :icone="adicionando ? 'i-lucide-x' : 'i-lucide-plus'"
        :aria-expanded="adicionando ? 'true' : 'false'"
        @click="alternarAdicionar"
      >
        {{ t(`${NS}.MANDAR`) }}
      </AgenteBotao>
    </template>

    <DialogoAcao
      ref="dialogoTirar"
      :titulo="t(`${NS}.TIRAR_TITULO`, { nome: nomeDaFonte(tirando) })"
      :texto="t(`${NS}.TIRAR_TEXTO`, { agente: nome })"
      :confirmar="t(`${NS}.TIRAR`)"
      variante="perigo"
      :erro-titulo="t(`${NS}.ERRO`)"
      :erro-garantia="t(`${NS}.ERRO_GARANTIA`)"
      :executar="tirar"
      @fechada="tirando = null"
    />
  </AgenteGaveta>
</template>
