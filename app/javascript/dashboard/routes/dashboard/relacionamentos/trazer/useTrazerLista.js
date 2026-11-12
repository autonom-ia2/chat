import { computed, onScopeDispose, ref } from 'vue';
import { SEM_ACESSO } from '../ficha/falhas';
import { ehPlanilha } from './arquivo';
import { resumoAoVivo, totalDaLeitura } from './contagem';
import { EVENTOS, estadoInicial, etapaDoTopo, proximo } from './etapas';
import { SITUACOES_DA_LISTA } from './prazo';

// #2894 — o estado de "Trazer minha lista": a etapa, a leitura da planilha, as
// respostas e o andamento. Fala só com a fonte (fonte/trazerFonte.js); quem
// desenha é a página.
// #2896 — quem o servidor recusa por falta de acesso liga `semAcesso` (a tela
// diz isso em vez de oferecer "tentar de novo"). A lista que para no meio não é
// "Pronto": a tela avisa e chama `aoFalhar`.
export const INTERVALO_DO_ANDAMENTO_MS = 1500;

// O que deu errado, para a tela escolher a frase.
export const ERROS = {
  NENHUM: '',
  TIPO: 'tipo',
  GRANDE: 'grande',
  LEITURA: 'leitura',
  VAZIA: 'vazia',
  SEM_CONTATO: 'sem_contato',
  TRAZER: 'trazer',
  ANDAMENTO: 'andamento',
};

// O nome que a fonte dá ao que o servidor recusou (fonte/trazerTraducao.js).
const ERROS_DA_LEITURA = new Map([
  ['PLANILHA_TIPO', ERROS.TIPO],
  ['PLANILHA_GRANDE', ERROS.GRANDE],
  ['PLANILHA_VAZIA', ERROS.VAZIA],
  ['PLANILHA_SEM_CONTATO', ERROS.SEM_CONTATO],
]);

const AVISO_ERRO_GUARDAR = 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR';
const AVISO_ERRO_TRAZER = 'RELACIONAMENTOS_TRAZER.ERROS.TRAZER';
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
  aoFalhar = () => {},
  intervalo = INTERVALO_DO_ANDAMENTO_MS,
}) => {
  const estado = ref(estadoInicial());
  const leitura = ref(null);
  const respostas = ref({});
  const lendo = ref(false);
  const ocupado = ref(false);
  const erro = ref(ERROS.NENHUM);
  const semAcesso = ref(false);
  const porcentagem = ref(0);
  const totalTrazido = ref(0);
  const novasTrazidas = ref(0);
  const completadasTrazidas = ref(0);
  let ultimaEntrada = null;
  let trazidaId = null;
  let relogio = null;
  let encerrado = false;
  // Sobe a cada parar/recomeçar: uma resposta que volta de uma geração velha
  // (consulta em voo) é descartada em vez de mexer no estado zerado.
  let geracao = 0;

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

  // Devolve true quando a falha é a recusa por falta de acesso (e a registra).
  const recusado = falha => {
    if (falha?.name !== SEM_ACESSO) return false;
    semAcesso.value = true;
    return true;
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
    } catch (falha) {
      if (!recusado(falha)) {
        erro.value = ERROS_DA_LEITURA.get(falha?.name) ?? ERROS.LEITURA;
      }
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

  // Em demonstração a fonte pode oferecer um arquivo de mentira (para mostrar
  // os erros do arquivo sem precisar de um arquivo de verdade).
  const usarExemplo = () => {
    const exemplo = fonte.arquivoDeExemplo?.() ?? null;
    return exemplo ? escolherArquivo(exemplo) : ler(null);
  };

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
    } catch (falha) {
      if (!recusado(falha)) avisar(AVISO_ERRO_GUARDAR);
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
  const reabrir = linha =>
    escrever(() => fonte.reabrir(leitura.value.id, linha));
  const trocarDestino = (coluna, destino) =>
    escrever(() => fonte.trocarDestino(leitura.value.id, coluna, destino));

  const parar = () => {
    geracao += 1;
    clearTimeout(relogio);
    relogio = null;
  };

  const consultar = async () => {
    if (encerrado) return;
    const minha = geracao;
    const valeAinda = () => !encerrado && minha === geracao;
    try {
      const andamento = await fonte.andamento(trazidaId);
      if (!valeAinda()) return;
      porcentagem.value = andamento.porcentagem;
      totalTrazido.value = andamento.total;
      novasTrazidas.value = andamento.novas;
      completadasTrazidas.value = andamento.completadas;
      if (andamento.situacao === SITUACOES_DA_LISTA.FALHOU) {
        avisar(AVISO_ERRO_TRAZER);
        aoFalhar();
        return;
      }
      if (andamento.situacao !== SITUACOES_DA_LISTA.TRAZENDO) {
        ir(EVENTOS.TERMINOU);
        return;
      }
      relogio = setTimeout(consultar, intervalo);
    } catch (falha) {
      if (valeAinda() && !recusado(falha)) erro.value = ERROS.ANDAMENTO;
    }
  };

  const trazer = async () => {
    const minha = geracao;
    ocupado.value = true;
    erro.value = ERROS.NENHUM;
    try {
      const { trazidaId: id } = await fonte.trazer(leitura.value.id);
      if (encerrado || minha !== geracao) return;
      trazidaId = id;
    } catch (falha) {
      if (!encerrado && minha === geracao && !recusado(falha)) {
        erro.value = ERROS.TRAZER;
      }
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
    // A fonte real pode estar esperando a leitura da planilha: para de perguntar.
    fonte.encerrar?.();
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
    semAcesso,
    porcentagem,
    totalTrazido,
    novasTrazidas,
    completadasTrazidas,
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
    reabrir,
    trocarDestino,
    trazer,
    tentarDeNovo,
    recomecar,
  };
};
