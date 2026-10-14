<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import GrupoDeCartoes from './GrupoDeCartoes.vue';
import {
  BLOQUEIO,
  bloqueioDaCaixa,
  caixaPeloId,
  enderecoDaCaixa,
  mudancaDaEquipe,
  principalDaCaixa,
} from '../../utils/ondeTrabalha';

// #1433 (tema 13) — os passos do agente da equipe, numa gaveta: (1) em quais canais ele fica na
// equipe e (2) "Confira como fica". Usada no Comece da criação (`?papel=area`) e no "Mudar" de "Onde
// {nome} trabalha" na página do agente (abre direto nestes passos, recomendação aceita na rodada 3).
// - Só caixas com principal ATENDENDO podem ser escolhidas; as outras aparecem bloqueadas com o motivo
//   (ninguém atende primeiro, outro robô, ou o principal está parado).
// - "Confira" diz, por caixa, quem atende primeiro e que este agente recebe quando alguém passar; sem
//   nome ainda, "o agente que você está criando". No "Mudar", também quem sai.
// Quem chama grava (POST channels com papel area / DELETE) e passa `salvando` e `erro`.
// `canais`: a L2 (canais_ocupados), com `areas`; `caixas`: a store de inboxes (ícone e número).
const props = defineProps({
  nome: { type: String, required: true },
  semNome: { type: Boolean, default: false },
  agenteId: { type: Number, default: null },
  canais: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
  // 'carregando' | 'pronto' | 'erro', da leitura da L2.
  leitura: { type: String, default: 'pronto' },
  // Ids das caixas em que ele já está na equipe (Mudar).
  inicial: { type: Array, default: () => [] },
  salvando: { type: Boolean, default: false },
  // { titulo, garantia } da gravação que falhou, ou null.
  erro: { type: Object, default: null },
  textoFinal: { type: String, required: true },
  // O que o "Voltar" do primeiro passo diz (na criação, "Voltar ao teste").
  textoSair: { type: String, required: true },
  rotuloCarregando: { type: String, required: true },
});

const emit = defineEmits(['fechar', 'pronto', 'reler']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.EQUIPE';
const PASSOS = ['canais', 'confira'];

const indice = ref(0);
const escolhidas = ref([...props.inicial]);
// A leitura pode chegar depois de abrir: até a pessoa mexer, a escolha acompanha onde ele já está.
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

const MOTIVO = {
  [BLOQUEIO.SEM_PRINCIPAL]: () => t(`${NS}.SEM_PRINCIPAL`),
  [BLOQUEIO.PRINCIPAL_PARADO]: canal =>
    t(`${NS}.PRINCIPAL_PARADO`, {
      outro: principalDaCaixa(canal).agent_name,
    }),
};

const opcoes = computed(() =>
  props.canais.map(canal => {
    const caixa = caixaPeloId(props.caixas, canal.inbox_id);
    // Quem já está na equipe da caixa continua escolhível, mesmo se o principal parou (para poder sair).
    const bloqueio = props.inicial.includes(canal.inbox_id)
      ? null
      : bloqueioDaCaixa(canal, props.agenteId);
    const principal = principalDaCaixa(canal);
    return {
      valor: canal.inbox_id,
      inbox: caixa || { channel_type: canal.channel_type },
      titulo: canal.name,
      texto:
        principal && !bloqueio
          ? t(`${NS}.PRINCIPAL`, { outro: principal.agent_name })
          : enderecoDaCaixa(caixa),
      desabilitada: Boolean(bloqueio),
      motivo: bloqueio ? MOTIVO[bloqueio](canal) : '',
    };
  })
);
const algumaLivre = computed(() =>
  opcoes.value.some(opcao => !opcao.desabilitada)
);

const linhaDaCaixa = (inboxId, chave) => {
  const canal = props.canais.find(item => item.inbox_id === inboxId);
  const outro = principalDaCaixa(canal)?.agent_name || '';
  return {
    inboxId,
    nome: canal?.name || '',
    caixa: caixaPeloId(props.caixas, inboxId) || {
      channel_type: canal?.channel_type,
    },
    texto:
      chave === 'AVISO' && props.semNome
        ? t(`${NS}.AVISO_SEM_NOME`, { outro })
        : t(`${NS}.${chave}`, { outro, nome: props.nome }),
  };
};

const mudanca = computed(() =>
  mudancaDaEquipe(props.inicial, escolhidas.value)
);
const linhasDoConfira = computed(() => [
  ...escolhidas.value.map(id => ({ ...linhaDaCaixa(id, 'AVISO'), sai: false })),
  ...mudanca.value.saem.map(id => ({ ...linhaDaCaixa(id, 'SAI'), sai: true })),
]);

const mudou = computed(
  () => mudanca.value.entram.length > 0 || mudanca.value.saem.length > 0
);
const podeSeguir = computed(() =>
  passo.value === 'canais'
    ? escolhidas.value.length > 0 && mudou.value
    : !props.salvando
);

const focarTitulo = async () => {
  await nextTick();
  tituloDoPasso.value?.focus();
};

const seguir = () => {
  if (!podeSeguir.value) return;
  if (passo.value === 'confira') {
    emit('pronto', { escolhidas: escolhidas.value, ...mudanca.value });
    return;
  }
  indice.value += 1;
  focarTitulo();
};

const voltar = () => {
  if (props.salvando) return;
  if (indice.value === 0) {
    emit('fechar');
    return;
  }
  indice.value -= 1;
  focarTitulo();
};
</script>

<template>
  <AgenteGaveta
    :titulo="
      semNome
        ? t('AGENTS.JORNADA.ONDE.TITULO_SEM_NOME')
        : t('AGENTS.JORNADA.ONDE.TITULO', { nome })
    "
    @fechar="emit('fechar')"
  >
    <section
      data-equipe-canais
      :data-passo="passo"
      aria-labelledby="equipe-passo-titulo"
      class="flex flex-col gap-4"
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
        <h3
          id="equipe-passo-titulo"
          ref="tituloDoPasso"
          tabindex="-1"
          class="m-0 text-xl font-bold tracking-tight outline-none text-n-slate-12"
        >
          {{ passo === 'canais' ? comNome('TITULO') : t(`${NS}.CONFIRA`) }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
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
            v-else-if="escolhidas.length && !mudou"
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
    </section>

    <template #rodape>
      <AgenteBotao
        data-seguir-equipe
        tamanho="xl"
        bloco
        :icone-direita="passo === 'canais' ? 'i-lucide-arrow-right' : ''"
        :inativo="!podeSeguir"
        :carregando="salvando"
        :rotulo-carregando="rotuloCarregando"
        @click="seguir"
      >
        {{ passo === 'canais' ? t(`${NS}.CONTINUAR`) : textoFinal }}
      </AgenteBotao>
      <AgenteBotao
        data-voltar-equipe
        variante="fantasma"
        bloco
        :desabilitado="salvando"
        @click="voltar"
      >
        {{ passo === 'canais' ? textoSair : t(`${NS}.VOLTAR`) }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
