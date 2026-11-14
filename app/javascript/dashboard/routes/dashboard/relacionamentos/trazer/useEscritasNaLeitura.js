import { ESCRITA } from './estadoDoTrazer';
import { ERROS, NOMES, fraseDaEscrita, motivoDaRecusa } from './falhasDaTela';

// #2896, Fatia 2 — as escritas na leitura da tela "Trazer minha lista" (as
// partes de trazer/useTrazerLista.js que escrevem): o conserto de cada linha, a
// troca de destino de uma coluna e o "Mostrar mais". A resposta das perguntas
// está em trazer/usePerguntasDaLista.js e usa o mesmo `escrever`.
const LENDO = 'lendo';

const aoFalharAEscrita = async (tela, falha, noLugar) => {
  if (tela.recusado(falha) || tela.venceu(falha)) return ESCRITA.NAO_GRAVOU;
  if (falha?.name === NOMES.TELA_DESATUALIZADA) {
    await tela.reler({ porqueMudou: true });
    return ESCRITA.NAO_GRAVOU;
  }
  // A recusa fica dita no lugar da ação; o aviso solto é só reforço.
  if (!noLugar(falha)) tela.avisar(fraseDaEscrita(falha));
  return ESCRITA.NAO_GRAVOU;
};

export const useEscritaNaLeitura = tela => {
  const { ocupado, recusaDaColuna, recusaDaPergunta, mudou } = tela;

  // Escrever na leitura: a fonte devolve a leitura nova e a tela passa a usá-la.
  // Quando ela devolve o marcador `lendo`, a mudança está salva e a tela espera
  // a leitura de novo. `noLugar` põe a recusa no lugar da ação e devolve true
  // quando esse lugar já diz tudo (sem aviso de reforço).
  const escrever = (gravar, noLugar) => {
    if (ocupado.value) return ESCRITA.NAO_GRAVOU;
    recusaDaColuna.value = null;
    recusaDaPergunta.value = null;
    return tela.ocupando(async () => {
      try {
        const voltou = await gravar();
        if (voltou?.situacao === LENDO) return await tela.reler();
        tela.usarLeitura(voltou);
        mudou.value = false;
        return ESCRITA.GRAVOU;
      } catch (falha) {
        return aoFalharAEscrita(tela, falha, noLugar);
      }
    });
  };

  return { escrever };
};

export const useLinhasDaLeitura = tela => {
  const { fonte, leitura, recusaDoConserto, memoria } = tela;

  // Mexeu na linha: a recusa que ela tinha deixa de valer.
  const esquecerRecusa = linha => {
    if (recusaDoConserto.value?.linha === linha) recusaDoConserto.value = null;
  };

  // A escrita numa linha que não deu certo fica com a linha (um objeto novo a
  // cada recusa, para a linha dizer de novo mesmo com o mesmo motivo). A linha
  // diz a frase ali mesmo, como alerta: o aviso solto só repetiria.
  const escreverNaLinha = async (linha, gravar) => {
    memoria.veioDeUmaTroca = false;
    esquecerRecusa(linha);
    const gravou = await tela.escrever(gravar, falha => {
      recusaDoConserto.value = { linha, motivo: motivoDaRecusa(falha) };
      return true;
    });
    return Boolean(gravou);
  };

  const guardar = (linha, valor) =>
    escreverNaLinha(linha, () =>
      fonte.consertar(leitura.value.id, linha, valor)
    );
  const deixarDeFora = linha =>
    escreverNaLinha(linha, () => fonte.deixarDeFora(leitura.value.id, linha));
  const reabrir = linha =>
    escreverNaLinha(linha, () => fonte.reabrir(leitura.value.id, linha));

  return { guardar, deixarDeFora, reabrir };
};

export const useColunasDaLeitura = tela => {
  const { fonte, leitura, ocupado, recusaDaColuna, memoria } = tela;

  // `campo` só vem com a informação nova: o nome dela e o "para que serve".
  const trocarDestino = async (coluna, destino, ...campo) => {
    if (ocupado.value) return false;
    memoria.veioDeUmaTroca = true;
    const trocou = await tela.escrever(
      () => fonte.trocarDestino(leitura.value.id, coluna, destino, ...campo),
      falha => {
        recusaDaColuna.value = { coluna, chave: fraseDaEscrita(falha) };
        return false;
      }
    );
    if (trocou === ESCRITA.GRAVOU) tela.perguntarOQueFicouSemResposta();
    return Boolean(trocou);
  };

  return { trocarDestino };
};

const aoFalharOMais = async (tela, falha) => {
  if (tela.recusado(falha) || tela.venceu(falha)) return;
  if (falha?.name === NOMES.TELA_DESATUALIZADA) {
    await tela.ocupando(() => tela.reler({ porqueMudou: true }));
  } else if (falha?.name === NOMES.LEITURA_NAO_ENCONTRADA) {
    tela.voltarAoEnvio(ERROS.JA_TRAZIDA);
  } else {
    tela.erroDoMais.value = true;
  }
};

export const useMaisProblemas = tela => {
  const { fonte, leitura, ocupado, carregandoMais, erroDoMais } = tela;

  // "Mostrar mais": a página seguinte das linhas que precisam da pessoa.
  const mostrarMais = async () => {
    if (carregandoMais.value || ocupado.value) return;
    carregandoMais.value = true;
    erroDoMais.value = false;
    try {
      leitura.value = await fonte.maisProblemas(leitura.value.id);
    } catch (falha) {
      await aoFalharOMais(tela, falha);
    } finally {
      carregandoMais.value = false;
    }
  };

  return { mostrarMais };
};
