import { EVENTOS, ETAPAS } from './etapas';
import { AVISO_ERRO_TRAZER, ERROS, NOMES } from './falhasDaTela';
import { useAndamentoDaLista } from './useAndamentoDaLista';

// #2896, Fatia 2 — o trazer da tela "Trazer minha lista" (as partes de
// trazer/useTrazerLista.js que cuidam dele): o pedido, o andamento da lista que
// está sendo trazida e o "tentar de novo" de cada coisa que pode parar.

// A lista que para no meio não é "Pronto": a tela avisa e chama `aoFalhar`.
export const useAndamentoDaTela = tela => {
  const { fonte, intervalo, avisar, aoFalhar, erro } = tela;
  const andamento = useAndamentoDaLista({
    fonte,
    intervalo,
    aoTerminar: () => tela.ir(EVENTOS.TERMINOU),
    aoParar: () => {
      avisar(AVISO_ERRO_TRAZER);
      aoFalhar();
    },
    aoFalhar: falha => {
      if (!tela.recusado(falha)) erro.value = ERROS.ANDAMENTO;
    },
  });
  return { andamento };
};

const aoFalharOTrazer = async (tela, falha) => {
  if (tela.recusado(falha) || tela.venceu(falha)) return;
  if (falha?.name === NOMES.TELA_DESATUALIZADA) {
    await tela.reler({ porqueMudou: true });
    return;
  }
  // E3 — falta dizer quem é cliente: a tela vai à pergunta, que diz por quê.
  if (
    falha?.name === NOMES.FALTA_VALORES_CLIENTE &&
    (await tela.pedirOsValoresDeCliente())
  ) {
    return;
  }
  tela.erro.value =
    falha?.name === NOMES.NADA_PARA_TRAZER
      ? ERROS.NADA_PARA_TRAZER
      : ERROS.TRAZER;
};

export const useTrazerAgora = tela => {
  const { fonte, estado, leitura, ocupado, erro, memoria, andamento } = tela;

  // O id da lista trazida, ou null quando não trouxe (ou a tela já é outra).
  const pedirParaTrazer = async minha => {
    const valeAinda = () => !memoria.encerrado && minha === andamento.geracao();
    try {
      const { trazidaId: id } = await fonte.trazer(leitura.value.id);
      return valeAinda() ? id : null;
    } catch (falha) {
      if (valeAinda()) await aoFalharOTrazer(tela, falha);
      return null;
    }
  };

  // Um trazer por vez, e só a partir do Conferir: o segundo clique não pede de
  // novo nem abre outra cadeia de consultas.
  const trazer = async () => {
    if (ocupado.value || estado.value.etapa !== ETAPAS.CONFERIR) return;
    memoria.veioDeUmaTroca = false;
    erro.value = ERROS.NENHUM;
    const minha = andamento.parar();
    const id = await tela.ocupando(() => pedirParaTrazer(minha));
    if (id === null) return;
    tela.ir(EVENTOS.TRAZER);
    await andamento.acompanhar(id);
  };

  return { trazer };
};

// "Tentar de novo" só pergunta de novo ou repete o que não chegou a ser feito:
// nunca repete uma escrita que o servidor já tem.
export const useTentarDeNovo = tela => {
  const { releituraParada, erro, memoria, andamento } = tela;

  const tentarDeNovo = async () => {
    if (releituraParada.value) {
      await tela.ocupando(() => tela.reler());
    } else if (memoria.leituraPendente.value !== null) {
      await tela.retomar(memoria.leituraPendente.value);
    } else if (erro.value === ERROS.LEITURA && memoria.ultimaEntrada) {
      await tela.ler(memoria.ultimaEntrada.arquivo);
    } else if (erro.value === ERROS.TRAZER) {
      await tela.trazer();
    } else if (erro.value === ERROS.ANDAMENTO) {
      erro.value = ERROS.NENHUM;
      await andamento.consultarDeNovo();
    }
  };

  return { tentarDeNovo };
};
