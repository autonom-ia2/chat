import { computed, onScopeDispose, ref } from 'vue';
import { ehPlanilha } from './arquivo';
import { resumoAoVivo, totalDaLeitura } from './contagem';
import { EVENTOS, estadoInicial, etapaDoTopo, proximo } from './etapas';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — o estado de "Trazer minha lista": a etapa, a leitura da planilha, as
// respostas e o andamento. Fala só com a fonte (fonte/trazerFonte.js); quem
// desenha é a página.
export const INTERVALO_DO_ANDAMENTO_MS = 1500;

// O que deu errado, para a tela escolher a frase.
export const ERROS = {
  NENHUM: '',
  TIPO: 'tipo',
  LEITURA: 'leitura',
  TRAZER: 'trazer',
  ANDAMENTO: 'andamento',
};

const AVISO_ERRO_GUARDAR = 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR';
const PERGUNTA_CLIENTES = 'clientes';
const RESPOSTA_ALGUMAS = 'algumas';

const responderPergunta = (respostas, pergunta, valor) => {
  const novas = { ...respostas, [pergunta]: valor };
  if (pergunta === PERGUNTA_CLIENTES && valor !== RESPOSTA_ALGUMAS) {
    delete novas.colunaCliente;
  }
  return novas;
};

const perguntaRespondida = (pergunta, respostas) => {
  if (!pergunta) return true;
  if (pergunta.id !== PERGUNTA_CLIENTES) return Boolean(respostas[pergunta.id]);
  if (respostas.clientes === RESPOSTA_ALGUMAS) {
    return Boolean(respostas.colunaCliente);
  }
  return Boolean(respostas.clientes);
};

export const useTrazerLista = ({
  fonte,
  avisar = () => {},
  intervalo = INTERVALO_DO_ANDAMENTO_MS,
}) => {
  const estado = ref(estadoInicial());
  const leitura = ref(null);
  const respostas = ref({});
  const lendo = ref(false);
  const ocupado = ref(false);
  const erro = ref(ERROS.NENHUM);
  const porcentagem = ref(0);
  const totalTrazido = ref(0);
  let ultimaEntrada = null;
  let trazidaId = null;
  let relogio = null;
  let encerrado = false;

  const etapa = computed(() => estado.value.etapa);
  const etapaAtualDoTopo = computed(() => etapaDoTopo(estado.value));
  const perguntaAtual = computed(
    () => leitura.value?.perguntas?.[estado.value.pergunta] ?? null
  );
  const podeContinuar = computed(() =>
    perguntaRespondida(perguntaAtual.value, respostas.value)
  );
  const resumo = computed(() => resumoAoVivo(leitura.value));
  const totalAtrazer = computed(() => totalDaLeitura(leitura.value));

  const ir = tipo => {
    estado.value = proximo(estado.value, { tipo });
  };

  const ler = async arquivo => {
    ultimaEntrada = { arquivo };
    lendo.value = true;
    erro.value = ERROS.NENHUM;
    try {
      const lida = await fonte.ler(arquivo);
      leitura.value = lida;
      respostas.value = {};
      estado.value = proximo(estado.value, {
        tipo: EVENTOS.LEU,
        perguntas: lida.perguntas.length,
      });
    } catch {
      erro.value = ERROS.LEITURA;
    } finally {
      lendo.value = false;
    }
  };

  const escolherArquivo = async arquivo => {
    if (!ehPlanilha(arquivo?.name)) {
      erro.value = ERROS.TIPO;
      return;
    }
    await ler(arquivo);
  };

  const usarExemplo = () => ler(null);

  const responder = (pergunta, valor) => {
    respostas.value = responderPergunta(respostas.value, pergunta, valor);
  };
  const escolherColunaDeCliente = coluna => {
    respostas.value = { ...respostas.value, colunaCliente: coluna };
  };

  // Escrever na leitura: a fonte devolve a leitura nova e a tela passa a usá-la.
  const escrever = async gravar => {
    ocupado.value = true;
    try {
      leitura.value = await gravar();
      return true;
    } catch {
      avisar(AVISO_ERRO_GUARDAR);
      return false;
    } finally {
      ocupado.value = false;
    }
  };

  const continuar = async () => {
    const ultima = estado.value.pergunta >= estado.value.totalDePerguntas - 1;
    if (ultima) {
      const gravou = await escrever(() =>
        fonte.responder(leitura.value.id, respostas.value)
      );
      if (!gravou) return;
    }
    ir(EVENTOS.CONTINUAR);
  };

  const voltar = () => ir(EVENTOS.VOLTAR);

  const guardar = (linha, valor) =>
    escrever(() => fonte.consertar(leitura.value.id, linha, valor));
  const deixarDeFora = linha =>
    escrever(() => fonte.deixarDeFora(leitura.value.id, linha));
  const trocarDestino = (coluna, destino) =>
    escrever(() => fonte.trocarDestino(leitura.value.id, coluna, destino));

  const parar = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  const consultar = async () => {
    if (encerrado) return;
    try {
      const andamento = await fonte.andamento(trazidaId);
      if (encerrado) return;
      porcentagem.value = andamento.porcentagem;
      totalTrazido.value = andamento.total;
      if (andamento.situacao !== SITUACOES_DA_LISTA.TRAZENDO) {
        ir(EVENTOS.TERMINOU);
        return;
      }
      relogio = setTimeout(consultar, intervalo);
    } catch {
      erro.value = ERROS.ANDAMENTO;
    }
  };

  const trazer = async () => {
    ocupado.value = true;
    erro.value = ERROS.NENHUM;
    try {
      ({ trazidaId } = await fonte.trazer(leitura.value.id));
    } catch {
      erro.value = ERROS.TRAZER;
      return;
    } finally {
      ocupado.value = false;
    }
    porcentagem.value = 0;
    ir(EVENTOS.TRAZER);
    await consultar();
  };

  const tentarDeNovo = async () => {
    if (erro.value === ERROS.LEITURA && ultimaEntrada) {
      await ler(ultimaEntrada.arquivo);
    } else if (erro.value === ERROS.TRAZER) {
      await trazer();
    } else if (erro.value === ERROS.ANDAMENTO) {
      erro.value = ERROS.NENHUM;
      await consultar();
    }
  };

  const recomecar = () => {
    parar();
    estado.value = estadoInicial();
    leitura.value = null;
    respostas.value = {};
    erro.value = ERROS.NENHUM;
    porcentagem.value = 0;
    ultimaEntrada = null;
    trazidaId = null;
  };

  onScopeDispose(() => {
    encerrado = true;
    parar();
  });

  return {
    estado,
    etapa,
    etapaAtualDoTopo,
    leitura,
    respostas,
    lendo,
    ocupado,
    erro,
    porcentagem,
    totalTrazido,
    perguntaAtual,
    podeContinuar,
    resumo,
    totalAtrazer,
    escolherArquivo,
    usarExemplo,
    responder,
    escolherColunaDeCliente,
    continuar,
    voltar,
    guardar,
    deixarDeFora,
    trocarDestino,
    trazer,
    tentarDeNovo,
    recomecar,
  };
};
