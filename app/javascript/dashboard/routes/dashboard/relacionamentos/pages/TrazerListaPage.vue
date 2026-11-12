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
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import AvisosDaLeitura from '../components/trazer/AvisosDaLeitura.vue';
import DialogoDesfazer from '../components/trazer/DialogoDesfazer.vue';
import EtapasDoTopo from '../components/trazer/EtapasDoTopo.vue';
import HistoricoDeListas from '../components/trazer/HistoricoDeListas.vue';
import PerguntaDaVez from '../components/trazer/PerguntaDaVez.vue';
import TelaConferir from '../components/trazer/TelaConferir.vue';
import TelaEnviar from '../components/trazer/TelaEnviar.vue';
import TelaPronto from '../components/trazer/TelaPronto.vue';

// #2894 — "Trazer minha lista": uma entrada só, em três etapas (Enviar →
// Conferir → Pronto), com o histórico e o Desfazer. A tela não lê o arquivo no
// navegador: quem lê é a fonte (fonte/trazerFonte.js), no servidor (#2896) ou,
// em demonstração, com a leitura fictícia.
// O Desfazer só existe na tela quando a fonte diz que tem (`temDesfazer`): sem
// ele não há o botão no histórico, nem o diálogo, nem a frase que o promete.
// Fatia 2 — a leitura em aberto fica na rota (`?leitura=<id>`, só fora da
// demonstração): quem recarrega a página continua de onde estava, sem enviar a
// planilha de novo. O parâmetro sai quando a leitura deixa de estar em aberto
// (a pessoa recomeçou, trouxe a lista, ou a leitura já tinha sido trazida).
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const demo = usarDemo(route.query);
// `?planilha=` só vale em demonstração (e a demonstração só existe no DEV).
const planilha = demo && import.meta.env.DEV ? route.query.planilha : undefined;
const fonte = trazerFonte({ demo, planilha });
const temDesfazer = Boolean(fonte.temDesfazer);
const avisar = chave => useAlert(t(chave));

const historico = useHistoricoDeListas({ fonte, avisar });
// #2896 — a lista que falha no meio volta ao começo, onde o histórico diz que
// ela não foi trazida e oferece o "Tentar de novo".
const tela = useTrazerLista({
  fonte,
  avisar,
  aoFalhar: () => {
    tela.recomecar();
    historico.carregar();
  },
});
// O servidor recusou por falta de permissão (401): a pessoa não pode trazer
// listas nesta conta. Não é erro de tentar de novo; fica só a frase.
const semAcesso = computed(
  () => tela.semAcesso.value || historico.semAcesso.value
);

const raiz = ref(null);
const dialogo = ref(null);

const trazendo = computed(() => tela.etapa.value === ETAPAS.TRAZENDO);
const noFim = computed(() =>
  [ETAPAS.TRAZENDO, ETAPAS.PRONTO].includes(tela.etapa.value)
);

const chegou = computed(() => tela.etapa.value === ETAPAS.PRONTO);
// As telas que mostram a leitura da planilha: as perguntas e o conferir.
const naLeitura = computed(() =>
  [ETAPAS.PERGUNTAS, ETAPAS.CONFERIR].includes(tela.etapa.value)
);

// A leitura que a rota guarda (um texto só; o parâmetro repetido não vale).
const leituraDaRota = () => {
  const id = route.query.leitura;
  return typeof id === 'string' && id ? id : null;
};

onMounted(() => {
  historico.carregar();
  // `?planilha=` (só em demonstração) já cai no estado pedido, sem clique.
  if (fonte.planilhaDeDemo) tela.usarExemplo();
  else if (!demo && leituraDaRota()) tela.retomar(leituraDaRota());
});

// A rota acompanha a leitura em aberto. Enquanto a página pergunta pela
// leitura que a rota trouxe, o parâmetro fica como está.
watch(
  () => (tela.lendo.value ? leituraDaRota() : tela.leituraEmAberto.value),
  emAberto => {
    if (demo) return;
    const id = emAberto === null ? null : String(emAberto);
    if (id === leituraDaRota()) return;
    router.replace({ query: { ...route.query, leitura: id ?? undefined } });
  }
);

// A leitura já tinha sido trazida (em outra aba, ou por outra pessoa): a lista
// dela está no histórico, que a tela mostra de novo.
watch(
  () => tela.erro.value,
  erro => {
    if (erro === ERROS.JA_TRAZIDA) historico.carregar({ silencioso: true });
  }
);

// A pergunta da vez: a posição e qual é (depois de uma escrita, a mesma posição
// pode passar a ser de outra pergunta).
const chaveDaPergunta = computed(
  () => `${tela.estado.value.pergunta}:${tela.perguntaAtual.value?.id ?? ''}`
);

// A cada tela nova o foco vai para o título dela (leitor de tela e teclado).
watch(
  () => [tela.etapa.value, chaveDaPergunta.value],
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

// Aceito o pedido, o botão Desfazer da linha some. O diálogo, ao fechar,
// devolveria o foco a ele: sem o botão, o foco cairia no começo da página.
// Vai para a linha da lista, que agora diz "Desfazendo…".
const focarALinha = async id => {
  await nextTick();
  [...(raiz.value?.querySelectorAll('[data-lista]') ?? [])]
    .find(linha => linha.dataset.lista === String(id))
    ?.focus();
};

const confirmarDesfazer = async () => {
  const id = historico.alvo.value?.id;
  if (!(await historico.confirmarDesfazer())) return;
  dialogo.value?.fechar();
  await focarALinha(id);
};

// Sem acesso (401) na prévia ou ao desfazer: a tela inteira vira a frase de
// sem acesso, e o diálogo não fica aberto por cima dela.
watch(semAcesso, sem => {
  if (sem) dialogo.value?.fechar();
});
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

        <p
          v-if="semAcesso"
          data-relacionamentos="sem-acesso"
          role="alert"
          class="p-5 m-0 text-base border rounded-2xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ t('RELACIONAMENTOS_TRAZER.SEM_ACESSO') }}
        </p>
        <template v-else>
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
              :tentando="historico.tentando.value"
              :tem-desfazer="temDesfazer"
              @desfazer="abrirDesfazer"
              @tentar="historico.carregar"
              @tentar-de-novo="historico.tentarDeNovo"
            />
          </template>

          <div
            v-else-if="tela.releituraParada.value"
            data-relacionamentos="releitura-parada"
          >
            <ErroComTentarDeNovo
              :mensagem="t('RELACIONAMENTOS_TRAZER.CONFERIR.RELEITURA_PAROU')"
              @tentar="tela.tentarDeNovo"
            />
          </div>

          <template v-else-if="naLeitura">
            <AvisosDaLeitura
              :aviso="tela.leitura.value.aviso"
              :mudou="tela.mudou.value"
            />
            <PerguntaDaVez
              v-if="tela.etapa.value === ETAPAS.PERGUNTAS"
              :key="chaveDaPergunta"
              :pergunta="tela.perguntaAtual.value"
              :respostas="tela.respostas.value"
              :colunas="tela.leitura.value.colunas"
              :tem-empresa="tela.leitura.value.temEmpresa"
              :pode-continuar="tela.podeContinuar.value"
              :ocupado="tela.ocupado.value"
              :relendo="tela.relendo.value"
              :de-novo="tela.perguntaDeNovo.value"
              :recusa="tela.recusaDaPergunta.value"
              @responder="tela.responder"
              @escolher-coluna="tela.escolherColunaDeCliente"
              @continuar="tela.continuar"
              @voltar="tela.voltar"
            />
            <TelaConferir
              v-else
              :leitura="tela.leitura.value"
              :resumo="tela.resumo.value"
              :total="tela.entram.value"
              :ocupado="tela.ocupado.value"
              :relendo="tela.relendo.value"
              :com-erro="tela.erro.value === ERROS.TRAZER"
              :recusa-do-conserto="tela.recusaDoConserto.value"
              :recusa-da-coluna="tela.recusaDaColuna.value"
              :recusa-do-trazer="tela.erro.value"
              :faltam-carregar="tela.faltamCarregar.value"
              :carregando-mais="tela.carregandoMais.value"
              :erro-do-mais="tela.erroDoMais.value"
              :tem-desfazer="temDesfazer"
              @guardar="tela.guardar"
              @deixar-de-fora="tela.deixarDeFora"
              @reabrir="tela.reabrir"
              @trocar="tela.trocarDestino"
              @mostrar-mais="tela.mostrarMais"
              @trazer="tela.trazer"
              @escolher-outra="trazerOutra"
              @voltar="tela.voltar"
              @tentar="tela.tentarDeNovo"
            />
          </template>

          <TelaPronto
            v-else-if="noFim"
            :trazendo="trazendo"
            :porcentagem="tela.porcentagem.value"
            :novas="tela.novasTrazidas.value"
            :completadas="tela.completadasTrazidas.value"
            :com-erro="tela.erro.value === ERROS.ANDAMENTO"
            :tem-desfazer="temDesfazer"
            @ver="verAsPessoas"
            @outra="trazerOutra"
            @tentar="tela.tentarDeNovo"
          />

          <HistoricoDeListas
            v-if="chegou"
            :listas="historico.listas.value"
            :carregando="historico.carregando.value"
            :com-erro="historico.erro.value"
            :tentando="historico.tentando.value"
            :tem-desfazer="temDesfazer"
            @desfazer="abrirDesfazer"
            @tentar="historico.carregar"
            @tentar-de-novo="historico.tentarDeNovo"
          />
        </template>
      </div>
    </main>

    <DialogoDesfazer
      v-if="temDesfazer"
      ref="dialogo"
      :arquivo="historico.alvo.value?.arquivo"
      :previa="historico.previa.value"
      :com-erro-na-previa="historico.previaComErro.value"
      :desfazendo="historico.desfazendo.value"
      :nao-pode="historico.naoPodeDesfazer.value"
      @confirmar="confirmarDesfazer"
      @fechar="historico.fecharDesfazer"
      @tentar="() => historico.abrirDesfazer(historico.alvo.value)"
    />
  </section>
</template>
