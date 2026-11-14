import { computed, ref } from 'vue';
import { ehSemAcesso } from '../lista/falhas';
import { problemasPorCarregar, resumoDaTela } from './contagem';
import { ETAPAS, estadoInicial, etapaDoTopo, proximo } from './etapas';
import { ERROS, NOMES } from './falhasDaTela';
import { perguntaRespondida } from './respostas';

// #2896, Fatia 2 — o que a tela "Trazer minha lista" guarda (trazer/
// useTrazerLista.js) e os passos que todas as partes dela usam: andar de etapa,
// registrar a falta de acesso, marcar a escrita em voo e recomeçar.
const ETAPAS_DA_LEITURA = [ETAPAS.PERGUNTAS, ETAPAS.CONFERIR];

// Como terminou uma escrita na leitura (as duas que deram certo valem "sim").
export const ESCRITA = { NAO_GRAVOU: false, GRAVOU: 'gravou', RELEU: 'releu' };

// O que a página lê.
export const criarEstado = () => ({
  estado: ref(estadoInicial()),
  leitura: ref(null),
  respostas: ref({}),
  lendo: ref(false),
  ocupado: ref(false),
  relendo: ref(false),
  releituraParada: ref(false),
  mudou: ref(false),
  erro: ref(ERROS.NENHUM),
  semAcesso: ref(false),
  recusaDoConserto: ref(null),
  recusaDaColuna: ref(null),
  recusaDaPergunta: ref(null),
  perguntaDeNovo: ref(false),
  carregandoMais: ref(false),
  erroDoMais: ref(false),
});

// O que a tela lembra e a página não desenha.
export const criarMemoria = () => ({
  // A leitura que o servidor tem e que a tela ainda não conseguiu mostrar.
  leituraPendente: ref(null),
  // O arquivo do último envio, para o "tentar de novo".
  ultimaEntrada: null,
  encerrado: false,
  // A última escrita foi a troca de uma coluna (e ainda não se sabe em que tela
  // ela deixa a pessoa).
  veioDeUmaTroca: false,
});

export const derivadosDoEstado = ({ estado, leitura, respostas }, memoria) => {
  const perguntaAtual = computed(
    () => leitura.value?.perguntas?.[estado.value.pergunta] ?? null
  );
  const resumo = computed(() => resumoDaTela(leitura.value));
  return {
    etapa: computed(() => estado.value.etapa),
    etapaAtualDoTopo: computed(() => etapaDoTopo(estado.value)),
    perguntaAtual,
    podeContinuar: computed(() =>
      perguntaRespondida(perguntaAtual.value, respostas.value)
    ),
    resumo,
    entram: computed(() => resumo.value.entram),
    faltamCarregar: computed(() => problemasPorCarregar(leitura.value)),
    // O id que a rota guarda, para a página recarregada continuar de onde estava.
    leituraEmAberto: computed(() => {
      const pendente = memoria.leituraPendente.value;
      if (pendente !== null) return pendente;
      return ETAPAS_DA_LEITURA.includes(estado.value.etapa)
        ? (leitura.value?.id ?? null)
        : null;
    }),
  };
};

export const usePassosDaTela = ({ estado, semAcesso, ocupado }) => {
  const ir = tipo => {
    estado.value = proximo(estado.value, { tipo });
  };

  // Devolve true quando a falha é a recusa por falta de acesso (e a registra).
  const recusado = falha => {
    if (!ehSemAcesso(falha)) return false;
    semAcesso.value = true;
    return true;
  };

  const ocupando = async tarefa => {
    ocupado.value = true;
    try {
      return await tarefa();
    } finally {
      ocupado.value = false;
    }
  };

  return { ir, recusado, ocupando };
};

const limparEstado = tela => {
  const { memoria } = tela;
  tela.estado.value = estadoInicial();
  tela.leitura.value = null;
  tela.respostas.value = {};
  tela.erro.value = ERROS.NENHUM;
  tela.recusaDoConserto.value = null;
  tela.recusaDaColuna.value = null;
  tela.recusaDaPergunta.value = null;
  tela.releituraParada.value = false;
  tela.mudou.value = false;
  tela.perguntaDeNovo.value = false;
  tela.erroDoMais.value = false;
  memoria.leituraPendente.value = null;
  memoria.ultimaEntrada = null;
  memoria.veioDeUmaTroca = false;
};

export const useRecomeco = tela => {
  const recomecar = () => {
    tela.andamento.parar();
    limparEstado(tela);
  };

  // A leitura acabou: a tela volta ao Enviar e diz por quê.
  const voltarAoEnvio = motivo => {
    recomecar();
    tela.erro.value = motivo;
  };

  // Devolve true quando a falha é a conferência vencida (e volta ao Enviar, que
  // diz a frase fixa): não há o que tentar de novo com essa leitura.
  const venceu = falha => {
    if (falha?.name !== NOMES.CONFERENCIA_VENCIDA) return false;
    voltarAoEnvio(ERROS.VENCIDA);
    return true;
  };

  return { recomecar, voltarAoEnvio, venceu };
};
