<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import EsqueletoDeLista from '../../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import EtapasDoTopo from '../../trazer/EtapasDoTopo.vue';
import TelaEnviar from '../../trazer/TelaEnviar.vue';
import TelaPronto from '../../trazer/TelaPronto.vue';
import BuscandoNoAgger from './BuscandoNoAgger.vue';
import ComoTrazer from './ComoTrazer.vue';
import ConferirSeguros from './ConferirSeguros.vue';
import EnviarPdfs from './EnviarPdfs.vue';
import LigarAgger from './LigarAgger.vue';
import PerguntaDeSeguros from './PerguntaDeSeguros.vue';
import ProntoDeSeguros from './ProntoDeSeguros.vue';
import PassoOndeRenovacoes from '../renovacao/PassoOndeRenovacoes.vue';
import { COMO, PASSOS } from '../../../carteira/passosDeTrazerSeguros';
import { useBuscaNoAgger } from '../../../carteira/useBuscaNoAgger';
import { useComoNaUrl } from '../../../carteira/useComoNaUrl';
import { useLeituraDePdfs } from '../../../carteira/useLeituraDePdfs';
import { COMECO, useTrazerSeguros } from '../../../carteira/useTrazerSeguros';
import { ERROS } from '../../../trazer/useTrazerLista';

// #2897 — "Trazer clientes e seguros" na conta de seguros (telas 8, 9, 10, 16
// e 17): a escolha de como trazer e, de cada jeito, o caminho até o Pronto. Uma
// pergunta por tela; na primeira vez, antes de conferir, "Onde ficam as
// renovações?". O histórico ("O que você já trouxe") vem de quem usa, no
// slot `historico`, porque é o mesmo das listas de pessoas.
const props = defineProps({
  fonte: { type: Object, required: true },
  // Em demonstração aparecem a planilha e os PDFs de exemplo.
  mostrarExemplo: { type: Boolean, default: false },
});
const emit = defineEmits(['soPessoas', 'chegou', 'recomecou']);

const { t } = useI18n();
const router = useRouter();
const { como, mudar } = useComoNaUrl();
const avisar = chave => useAlert(t(chave));

const tela = useTrazerSeguros({
  fonte: props.fonte,
  como,
  mudarComo: mudar,
  avisar,
});
const pdfs = useLeituraDePdfs({ fonte: props.fonte, aoLer: tela.conferir });
const agger = useBuscaNoAgger({ fonte: props.fonte });

const raiz = ref(null);
const passo = computed(() => tela.passo.value);
const naEscolha = computed(() => passo.value === PASSOS.COMO);
// Enviar e ligar não têm Voltar próprio: ele fica no topo.
const voltaNoTopo = computed(() =>
  [PASSOS.ENVIAR, PASSOS.LIGAR].includes(passo.value)
);
const trazendo = computed(() => passo.value === PASSOS.TRAZENDO);
const chegou = computed(() => passo.value === PASSOS.PRONTO);

onMounted(tela.carregarComeco);

// Outro jeito de trazer (ou de volta à escolha): o que era do jeito antigo sai.
watch(como, () => {
  pdfs.escolherOutros();
  agger.limpar();
});

// A cada tela nova o foco vai para o título dela (leitor de tela e teclado).
watch(
  () => [passo.value, agger.buscando.value],
  async () => {
    await nextTick();
    raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
  }
);

watch(chegou, agora => {
  if (agora) emit('chegou');
});

const voltar = () => {
  if (passo.value === PASSOS.LIGAR) agger.limpar();
  tela.voltar();
};

const trazerMais = () => {
  pdfs.escolherOutros();
  tela.trazerMais();
  emit('recomecou');
};

// A aba Seguros da demonstração cheia é a que mostra a carteira.
const verOsSeguros = () =>
  router.push({
    name: 'relationships_home',
    query: {
      aba: 'seguros',
      ...(props.mostrarExemplo ? { demo: 'cheio' } : {}),
    },
  });

defineExpose({
  voltarAPergunta: tela.voltarAPergunta,
  recomecar: tela.recomecar,
});
</script>

<template>
  <div ref="raiz" data-carteira="trazer" class="flex flex-col gap-8">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <button
        v-if="voltaNoTopo"
        type="button"
        data-carteira="voltar-a-escolha"
        class="inline-flex items-center gap-1 p-0 text-sm bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="voltar"
      >
        <span
          class="i-lucide-chevron-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('RELACIONAMENTOS.COMUM.VOLTAR') }}
      </button>
      <router-link
        v-else
        :to="{ name: 'relationships_home' }"
        class="inline-flex items-center gap-1 text-sm rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        <span
          class="i-lucide-chevron-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('RELACIONAMENTOS_TRAZER.PESSOAS') }}
      </router-link>
      <EtapasDoTopo
        v-if="tela.etapaDoTopo.value"
        :atual="tela.etapaDoTopo.value"
        :trazendo="trazendo"
        :primeiro="
          como === COMO.AGGER
            ? t('RELACIONAMENTOS_CARTEIRA.TRAZER.AGGER.ETAPA_BUSCAR')
            : ''
        "
      />
    </div>

    <template v-if="naEscolha">
      <ComoTrazer
        :estado="tela.comeco.value"
        :agger-ligado="tela.aggerLigado.value"
        @continuar="mudar"
        @tentar="tela.carregarComeco"
      />
      <slot name="historico" />
    </template>

    <template v-else-if="passo === PASSOS.ENVIAR">
      <TelaEnviar
        v-if="como === COMO.PLANILHA"
        :lendo="tela.lendo.value"
        :erro="tela.erro.value"
        :mostrar-exemplo="mostrarExemplo"
        :apoio="t('RELACIONAMENTOS_CARTEIRA.TRAZER.PLANILHA.APOIO')"
        @arquivo="tela.escolherPlanilha"
        @exemplo="tela.usarPlanilhaDeExemplo"
        @tentar="tela.tentarDeNovo"
      />
      <EnviarPdfs
        v-else
        :arquivos="pdfs.arquivos.value"
        :lendo="pdfs.lendo.value"
        :lidos="pdfs.lidos.value"
        :erro="pdfs.erro.value"
        :mostrar-exemplo="mostrarExemplo"
        @arquivos="pdfs.escolher"
        @exemplo="pdfs.usarExemplo"
        @outros="pdfs.escolherOutros"
        @ler="pdfs.ler"
      />
    </template>

    <PerguntaDeSeguros
      v-else-if="passo === PASSOS.PERGUNTA"
      @tem-seguros="tela.conferir()"
      @so-pessoas="emit('soPessoas', tela.leitura.value.pessoas)"
      @voltar="tela.voltar"
    />

    <PassoOndeRenovacoes
      v-else-if="passo === PASSOS.ONDE"
      :funis="tela.renovacoes.value.funis"
      :vencimentos="tela.leitura.value.efeito.vencimentos"
      :sem-permissao="tela.renovacoes.value.semPermissao"
      :ocupado="tela.ocupado.value"
      @escolher="tela.escolherRenovacoes"
      @voltar="voltar"
    />

    <template v-else-if="passo === PASSOS.LIGAR">
      <BuscandoNoAgger
        v-if="agger.buscando.value"
        :busca="agger.busca.value"
        :terminou="agger.terminou.value"
        :nao-respondeu="agger.naoRespondeu.value"
        :buscando-de-novo="agger.buscandoDeNovo.value"
        @continuar="tela.conferir(agger.busca.value.leitura)"
        @buscar-de-novo="agger.buscarDeNovo"
        @tentar-agora="agger.tentarAgora"
      />
      <div
        v-else-if="tela.comeco.value === COMECO.CARREGANDO"
        data-carteira="carregando"
      >
        <EsqueletoDeLista :linhas="2" />
      </div>
      <div v-else-if="tela.comeco.value === COMECO.ERRO" data-carteira="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.ERRO')"
          @tentar="tela.carregarComeco"
        />
      </div>
      <LigarAgger
        v-else
        :ligado="tela.aggerLigado.value"
        :entrando="agger.entrando.value"
        :erro="agger.erroDoLogin.value"
        @entrar="agger.entrar"
        @buscar="agger.buscarNaContaLigada"
        @voltar="voltar"
      />
    </template>

    <ConferirSeguros
      v-else-if="passo === PASSOS.CONFERIR"
      :leitura="tela.leitura.value"
      :contadores="tela.contadores.value"
      :total="tela.total.value"
      :ocupado="tela.ocupado.value"
      :com-erro="tela.erro.value === ERROS.TRAZER"
      @guardar="tela.guardar"
      @deixar-de-fora="tela.deixarDeFora"
      @reabrir="tela.reabrir"
      @trocar="tela.trocarDestino"
      @trazer="tela.trazer"
      @voltar="tela.voltar"
      @tentar="tela.tentarDeNovo"
    />

    <TelaPronto
      v-else-if="trazendo"
      trazendo
      :porcentagem="tela.porcentagem.value"
      :com-erro="tela.erro.value === ERROS.ANDAMENTO"
      @tentar="tela.tentarDeNovo"
    />

    <template v-else>
      <ProntoDeSeguros
        :como="como"
        :seguros="tela.chegaram.value.seguros"
        :pessoas="tela.chegaram.value.pessoas"
        @ver="verOsSeguros"
        @outra="trazerMais"
      />
      <slot name="historico" />
    </template>
  </div>
</template>
