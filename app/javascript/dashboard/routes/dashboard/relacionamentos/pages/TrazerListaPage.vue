<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { usarDemo } from '../fonte/modoDemo';
import { trazerFonte } from '../fonte/trazerFonte';
import { ETAPAS } from '../trazer/etapas';
import { ERROS, useTrazerLista } from '../trazer/useTrazerLista';
import { useHistoricoDeListas } from '../trazer/useHistoricoDeListas';
import DialogoDesfazer from '../components/trazer/DialogoDesfazer.vue';
import EtapasDoTopo from '../components/trazer/EtapasDoTopo.vue';
import HistoricoDeListas from '../components/trazer/HistoricoDeListas.vue';
import PerguntaDaVez from '../components/trazer/PerguntaDaVez.vue';
import TelaConferir from '../components/trazer/TelaConferir.vue';
import TelaEnviar from '../components/trazer/TelaEnviar.vue';
import TelaPronto from '../components/trazer/TelaPronto.vue';

// #2894 — "Trazer minha lista": uma entrada só, em três etapas (Enviar →
// Conferir → Pronto), com o histórico e o Desfazer. O protótipo não lê o arquivo
// no navegador: a fonte (fonte/trazerFonte.js) devolve a leitura fictícia.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const demo = usarDemo(route.query);
// `?planilha=` só vale em demonstração (e a demonstração só existe no DEV).
const planilha = demo && import.meta.env.DEV ? route.query.planilha : undefined;
const fonte = trazerFonte({ demo, planilha });
const avisar = chave => useAlert(t(chave));

const tela = useTrazerLista({ fonte, avisar });
const historico = useHistoricoDeListas({ fonte, avisar });

const raiz = ref(null);
const dialogo = ref(null);

const trazendo = computed(() => tela.etapa.value === ETAPAS.TRAZENDO);
const noFim = computed(() =>
  [ETAPAS.TRAZENDO, ETAPAS.PRONTO].includes(tela.etapa.value)
);

const chegou = computed(() => tela.etapa.value === ETAPAS.PRONTO);

onMounted(() => {
  historico.carregar();
  // `?planilha=` (só em demonstração) já cai no estado pedido, sem clique.
  if (fonte.planilhaDeDemo) tela.usarExemplo();
});

// A cada tela nova o foco vai para o título dela (leitor de tela e teclado).
watch(
  () => [tela.etapa.value, tela.estado.value.pergunta],
  async () => {
    await nextTick();
    raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
  }
);

// Ao chegar no Pronto o histórico já traz a lista recém-trazida no topo.
watch(chegou, agora => {
  if (agora) historico.carregar({ silencioso: true });
});

const verAsPessoas = () => router.push({ name: 'relationships_home' });

const trazerOutra = () => {
  tela.recomecar();
  historico.carregar();
};

const abrirDesfazer = async lista => {
  const aberta = historico.abrirDesfazer(lista);
  dialogo.value?.abrir();
  await aberta;
};

const confirmarDesfazer = async () => {
  if (await historico.confirmarDesfazer()) dialogo.value?.fechar();
};
</script>

<template>
  <section
    ref="raiz"
    class="flex flex-col w-full h-full bg-n-surface-1"
    data-relacionamentos="trazer"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        data-relacionamentos="trazer-conteudo"
        class="flex flex-col w-full max-w-3xl gap-8 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <div class="flex flex-wrap items-center justify-between gap-4">
          <router-link
            :to="{ name: 'relationships_home' }"
            class="inline-flex items-center gap-1 text-sm min-h-11 rounded-lg text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            <span
              class="i-lucide-chevron-left size-4 rtl:rotate-180"
              aria-hidden="true"
            />
            {{ t('RELACIONAMENTOS_TRAZER.PESSOAS') }}
          </router-link>
          <EtapasDoTopo
            :atual="tela.etapaAtualDoTopo.value"
            :trazendo="trazendo"
          />
        </div>

        <template v-if="tela.etapa.value === ETAPAS.ENVIAR">
          <TelaEnviar
            :lendo="tela.lendo.value"
            :erro="tela.erro.value"
            :mostrar-exemplo="Boolean(demo)"
            @arquivo="tela.escolherArquivo"
            @exemplo="tela.usarExemplo"
            @tentar="tela.tentarDeNovo"
          />
          <HistoricoDeListas
            :listas="historico.listas.value"
            :carregando="historico.carregando.value"
            :com-erro="historico.erro.value"
            @desfazer="abrirDesfazer"
            @tentar="historico.carregar"
          />
        </template>

        <PerguntaDaVez
          v-else-if="tela.etapa.value === ETAPAS.PERGUNTAS"
          :key="tela.estado.value.pergunta"
          :pergunta="tela.perguntaAtual.value"
          :respostas="tela.respostas.value"
          :colunas="tela.leitura.value.colunas"
          :pode-continuar="tela.podeContinuar.value"
          :ocupado="tela.ocupado.value"
          @responder="tela.responder"
          @escolher-coluna="tela.escolherColunaDeCliente"
          @continuar="tela.continuar"
          @voltar="tela.voltar"
        />

        <TelaConferir
          v-else-if="tela.etapa.value === ETAPAS.CONFERIR"
          :leitura="tela.leitura.value"
          :resumo="tela.resumo.value"
          :total="tela.totalAtrazer.value"
          :ocupado="tela.ocupado.value"
          :com-erro="tela.erro.value === ERROS.TRAZER"
          @guardar="tela.guardar"
          @deixar-de-fora="tela.deixarDeFora"
          @reabrir="tela.reabrir"
          @trocar="tela.trocarDestino"
          @trazer="tela.trazer"
          @escolher-outra="trazerOutra"
          @voltar="tela.voltar"
          @tentar="tela.tentarDeNovo"
        />

        <TelaPronto
          v-else-if="noFim"
          :trazendo="trazendo"
          :porcentagem="tela.porcentagem.value"
          :novas="tela.novasTrazidas.value"
          :completadas="tela.completadasTrazidas.value"
          :com-erro="tela.erro.value === ERROS.ANDAMENTO"
          @ver="verAsPessoas"
          @outra="trazerOutra"
          @tentar="tela.tentarDeNovo"
        />

        <HistoricoDeListas
          v-if="chegou"
          :listas="historico.listas.value"
          :carregando="historico.carregando.value"
          :com-erro="historico.erro.value"
          @desfazer="abrirDesfazer"
          @tentar="historico.carregar"
        />
      </div>
    </main>

    <DialogoDesfazer
      ref="dialogo"
      :arquivo="historico.alvo.value?.arquivo"
      :previa="historico.previa.value"
      :com-erro-na-previa="historico.previaComErro.value"
      :desfazendo="historico.desfazendo.value"
      @confirmar="confirmarDesfazer"
      @fechar="historico.fecharDesfazer"
      @tentar="() => historico.abrirDesfazer(historico.alvo.value)"
    />
  </section>
</template>
