<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import GrupoDeCartoes from './GrupoDeCartoes.vue';
import {
  BLOQUEIO,
  bloqueioDaCaixa,
  caixaPeloId,
  enderecoDaCaixa,
  mudancaDaEquipe,
  principalDaCaixa,
  soDePessoas,
} from '../../utils/ondeTrabalha';
import { useAgenteIaPorCaixa } from '../../composables/useAgenteIaPorCaixa';

// #1433 (tema 13) — os passos do agente da equipe, como no protótipo aprovado (70a963b461): (1) em quais
// canais ele fica na equipe e (2) "Confira como fica", uma decisão por tela.
// - `modo` 'criar': no começo da criação, antes da conversa (página inteira). Nada é gravado aqui: quem
//   chama guarda a escolha na URL e grava o vínculo quando o agente começa a trabalhar.
// - `modo` 'mudar': o "Mudar" de "Onde {nome} trabalha" na página do agente (numa gaveta). Mostra também
//   quem sai, e quem chama grava (entram e saem).
// Podem ser escolhidas as caixas com principal ATENDENDO e as atendidas só por pessoas (sem principal e
// sem robô; ali o agente só recebe o que alguém passar). As outras aparecem bloqueadas com o motivo (outro
// robô, ou o principal não está atendendo). Sem nome ainda, "o agente que você está criando".
// `canais`: a L2 (canais_ocupados), com `areas`; `caixas`: a store de inboxes (ícone e número).
const props = defineProps({
  modo: {
    type: String,
    default: 'criar',
    validator: v => ['criar', 'mudar'].includes(v),
  },
  nome: { type: String, required: true },
  semNome: { type: Boolean, default: false },
  agenteId: { type: Number, default: null },
  canais: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
  // 'carregando' | 'pronto' | 'erro', da leitura da L2.
  leitura: { type: String, default: 'pronto' },
  // Ids das caixas já escolhidas (criar: escolha anterior; mudar: onde ele está na equipe agora).
  inicial: { type: Array, default: () => [] },
  salvando: { type: Boolean, default: false },
  // { titulo, garantia } da gravação que falhou, ou null (só no mudar).
  erro: { type: Object, default: null },
  textoFinal: { type: String, required: true },
  rotuloCarregando: { type: String, default: '' },
});

const emit = defineEmits(['voltar', 'pronto', 'reler']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.EQUIPE';
const PASSOS = ['canais', 'confira'];
const mudando = props.modo === 'mudar';

const indice = ref(0);
const escolhidas = ref([...props.inicial]);
// A leitura pode chegar depois de abrir: até a pessoa mexer, a escolha acompanha a inicial.
const mexeu = ref(false);
watch(
  () => props.inicial.join(','),
  () => {
    if (!mexeu.value) escolhidas.value = [...props.inicial];
  }
);
const escolher = valor => {
  mexeu.value = true;
  escolhidas.value = valor;
};
const tituloDoPasso = ref(null);
const passo = computed(() => PASSOS[indice.value]);

const comNome = chave =>
  props.semNome
    ? t(`${NS}.${chave}_SEM_NOME`)
    : t(`${NS}.${chave}`, { nome: props.nome });

// #1648 — com a aba "Agente de IA" por caixa, o canal com agente de outro sistema aceita.
const porCaixa = useAgenteIaPorCaixa();

const MOTIVO = {
  [BLOQUEIO.SEM_PRINCIPAL]: () => t(`${NS}.SEM_PRINCIPAL`),
  [BLOQUEIO.OUTRO_ROBO]: () => t(`${NS}.OUTRO_ROBO`),
  [BLOQUEIO.FORA_DO_ALCANCE]: () => t(`${NS}.FORA_DO_ALCANCE`),
  [BLOQUEIO.PRINCIPAL_PARADO]: canal =>
    t(`${NS}.PRINCIPAL_PARADO`, {
      outro: principalDaCaixa(canal).agent_name,
    }),
};

const opcoes = computed(() =>
  props.canais.map(canal => {
    const caixa = caixaPeloId(props.caixas, canal.inbox_id);
    // No Mudar, onde ele já está continua escolhível mesmo se o principal parou (para poder sair),
    // menos na caixa que a pessoa não alcança (regra G, #1788): lá o servidor recusa a mudança.
    const bloqueioDaLista = bloqueioDaCaixa(canal, props.agenteId, {
      comOutroSistema: porCaixa.value,
    });
    const bloqueio =
      mudando &&
      props.inicial.includes(canal.inbox_id) &&
      bloqueioDaLista !== BLOQUEIO.FORA_DO_ALCANCE
        ? null
        : bloqueioDaLista;
    const principal = principalDaCaixa(canal);
    let texto = enderecoDaCaixa(caixa);
    if (soDePessoas(canal)) texto = comNome('SO_PESSOAS');
    else if (principal && !bloqueio) {
      texto = t(`${NS}.PRINCIPAL`, { outro: principal.agent_name });
    }
    return {
      valor: canal.inbox_id,
      inbox: caixa || { channel_type: canal.channel_type },
      titulo: canal.name,
      texto,
      desabilitada: Boolean(bloqueio),
      motivo: bloqueio ? MOTIVO[bloqueio](canal) : '',
    };
  })
);
const algumaLivre = computed(() =>
  opcoes.value.some(opcao => !opcao.desabilitada)
);
// Na criação só valem as escolhidas que ainda podem ser escolhidas (a URL pode ter ficado velha).
const validas = computed(() =>
  escolhidas.value.filter(id =>
    opcoes.value.some(opcao => opcao.valor === id && !opcao.desabilitada)
  )
);

const linhaDaCaixa = (inboxId, chaveDoPapel) => {
  const canal = props.canais.find(item => item.inbox_id === inboxId);
  const outro = principalDaCaixa(canal)?.agent_name || '';
  // Na caixa só de pessoas não há quem atenda primeiro: o texto fala das pessoas.
  const chave = soDePessoas(canal) ? `${chaveDoPapel}_PESSOAS` : chaveDoPapel;
  return {
    inboxId,
    nome: canal?.name || '',
    caixa: caixaPeloId(props.caixas, inboxId) || {
      channel_type: canal?.channel_type,
    },
    texto:
      chaveDoPapel === 'AVISO' && props.semNome
        ? t(`${NS}.${chave}_SEM_NOME`, { outro })
        : t(`${NS}.${chave}`, { outro, nome: props.nome }),
  };
};

// A caixa fora do alcance (regra G, #1788) não entra nem sai: o servidor a mantém como está.
const inicialAlcancavel = computed(() =>
  props.inicial.filter(
    id => props.canais.find(canal => canal.inbox_id === id)?.alcanca !== false
  )
);
const mudanca = computed(() =>
  mudancaDaEquipe(mudando ? inicialAlcancavel.value : [], validas.value)
);
const linhasDoConfira = computed(() => [
  ...validas.value.map(id => ({ ...linhaDaCaixa(id, 'AVISO'), sai: false })),
  ...mudanca.value.saem.map(id => ({ ...linhaDaCaixa(id, 'SAI'), sai: true })),
]);

const mudou = computed(
  () =>
    !mudando || mudanca.value.entram.length > 0 || mudanca.value.saem.length > 0
);
const podeSeguir = computed(() =>
  passo.value === 'canais'
    ? validas.value.length > 0 && mudou.value
    : !props.salvando
);

const focarTitulo = async () => {
  await nextTick();
  tituloDoPasso.value?.focus();
};

const seguir = () => {
  if (!podeSeguir.value) return;
  if (passo.value === 'confira') {
    emit('pronto', { escolhidas: validas.value, ...mudanca.value });
    return;
  }
  indice.value += 1;
  focarTitulo();
};

const voltar = () => {
  if (props.salvando) return;
  if (indice.value === 0) {
    emit('voltar');
    return;
  }
  indice.value -= 1;
  focarTitulo();
};

// Na criação é uma tela nova: o foco vai ao título do passo. Na gaveta, a gaveta cuida do foco.
onMounted(() => {
  if (!mudando) focarTitulo();
});
</script>

<template>
  <section
    data-equipe-canais
    :data-passo="passo"
    aria-labelledby="equipe-passo-titulo"
    class="flex flex-col gap-6"
    :aria-busy="salvando ? 'true' : undefined"
  >
    <header class="flex flex-col gap-2">
      <p
        data-progresso
        class="flex items-center gap-2 m-0 text-sm font-medium text-n-slate-11"
      >
        <span aria-hidden="true" class="flex gap-1">
          <span
            v-for="n in PASSOS.length"
            :key="n"
            class="h-1.5 rounded-full transition-all"
            :class="n <= indice + 1 ? 'w-6 bg-n-blue-11' : 'w-3 bg-n-slate-5'"
          />
        </span>
        {{ t(`${NS}.PASSO`, { n: indice + 1, total: PASSOS.length }) }}
      </p>
      <h2
        id="equipe-passo-titulo"
        ref="tituloDoPasso"
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none md:text-3xl text-n-slate-12"
      >
        {{ passo === 'canais' ? comNome('TITULO') : t(`${NS}.CONFIRA`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ passo === 'canais' ? t(`${NS}.TEXTO`) : t(`${NS}.CONFIRA_TEXTO`) }}
      </p>
    </header>

    <template v-if="passo === 'canais'">
      <p v-if="leitura === 'carregando'" role="status" class="m-0 text-sm">
        {{ t(`${NS}.CARREGANDO`) }}
      </p>
      <AgenteErro
        v-else-if="leitura === 'erro'"
        data-erro-ler
        tom="ambar"
        :titulo="t(`${NS}.ERRO_LER`)"
        :garantia="t(`${NS}.ERRO_LER_GARANTIA`, { nome })"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="emit('reler')"
      />
      <template v-else>
        <GrupoDeCartoes
          :model-value="escolhidas"
          :rotulo="comNome('TITULO')"
          :opcoes="opcoes"
          @update:model-value="escolher"
        />
        <p
          v-if="!algumaLivre"
          data-nenhum-principal
          class="p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
        >
          {{ t(`${NS}.NENHUM`) }}
        </p>
        <p
          v-else-if="validas.length && !mudou"
          data-sem-mudanca
          class="m-0 text-sm text-n-slate-11"
        >
          {{ t(`${NS}.SEM_MUDANCA`) }}
        </p>
      </template>
    </template>

    <ul
      v-else
      data-confira-equipe
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li
        v-for="linha in linhasDoConfira"
        :key="linha.inboxId"
        :data-sai="linha.sai ? '' : undefined"
        class="flex items-start gap-4 p-4 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset"
        :class="linha.sai ? 'ring-n-amber-6' : 'ring-n-weak'"
      >
        <span
          aria-hidden="true"
          class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-alpha-2"
        >
          <ChannelIcon :inbox="linha.caixa" use-brand-icon class="size-6" />
        </span>
        <span class="flex flex-col gap-1 min-w-0">
          <span class="text-base font-semibold text-n-slate-12">
            {{ linha.nome }}
          </span>
          <span class="text-sm text-n-slate-12">{{ linha.texto }}</span>
        </span>
      </li>
    </ul>

    <AgenteErro
      v-if="erro && passo === 'confira'"
      data-erro-salvar
      :titulo="erro.titulo"
      :garantia="erro.garantia"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="seguir"
    />

    <footer
      class="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <AgenteBotao
        data-voltar-equipe
        variante="fantasma"
        icone="i-lucide-arrow-left"
        :desabilitado="salvando"
        @click="voltar"
      >
        {{ t(`${NS}.VOLTAR`) }}
      </AgenteBotao>
      <AgenteBotao
        data-seguir-equipe
        tamanho="lg"
        class="max-sm:w-full"
        :icone-direita="passo === 'canais' ? 'i-lucide-arrow-right' : ''"
        :inativo="!podeSeguir"
        :carregando="salvando"
        :rotulo-carregando="rotuloCarregando"
        @click="seguir"
      >
        {{ passo === 'canais' ? t(`${NS}.CONTINUAR`) : textoFinal }}
      </AgenteBotao>
    </footer>
  </section>
</template>
