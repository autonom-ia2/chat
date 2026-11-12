// #2897 — o estado de "trazer seguros": a escolha de como trazer, a leitura (da
// planilha, dos PDFs ou do Agger), a conferência e o andamento. Fala só com a
// fonte (fonte/trazerSegurosFonte.js); quem desenha são as peças da tela.
// `como` vem do endereço (useComoNaUrl) e `mudarComo` o troca.
import { computed, onScopeDispose, ref, watch } from 'vue';
import { ehPlanilha } from '../trazer/arquivo';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';
import { ERROS, ERROS_DA_LEITURA } from '../trazer/useTrazerLista';
import { acompanhar } from './acompanhar';
import { contadoresDaLeitura, totalDeSeguros } from './contagemDeSeguros';
import {
  PASSOS,
  etapaDoTopoDe,
  passoAnterior,
  primeiroPasso,
} from './passosDeTrazerSeguros';

export const INTERVALO_DO_ANDAMENTO_MS = 1500;

export const COMECO = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
};

const AVISO_ERRO_SALVAR =
  'RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.ERRO_SALVAR';

export const useTrazerSeguros = ({
  fonte,
  como,
  mudarComo,
  avisar = () => {},
  intervalo = INTERVALO_DO_ANDAMENTO_MS,
}) => {
  const passo = ref(primeiroPasso(como.value));
  const comeco = ref(COMECO.CARREGANDO);
  const aggerLigado = ref(false);
  // Onde ficam as renovações: se a conta já escolheu, os funis dela e se quem
  // está usando pode mexer neles.
  const renovacoes = ref({ escolhido: true, funis: [], semPermissao: false });
  const leitura = ref(null);
  const lendo = ref(false);
  const ocupado = ref(false);
  const erro = ref(ERROS.NENHUM);
  const porcentagem = ref(0);
  const chegaram = ref({ seguros: 0, pessoas: 0 });
  let ultimaPlanilha = null;
  let trazidaId = null;
  let vigia = null;

  const etapaDoTopo = computed(() => etapaDoTopoDe(passo.value));
  const total = computed(() => totalDeSeguros(leitura.value));
  const contadores = computed(() => contadoresDaLeitura(leitura.value));

  const parar = () => {
    vigia?.parar();
    vigia = null;
  };

  const zerar = () => {
    parar();
    leitura.value = null;
    lendo.value = false;
    erro.value = ERROS.NENHUM;
    porcentagem.value = 0;
    ultimaPlanilha = null;
    trazidaId = null;
  };

  // O endereço mudou (a escolha, o Voltar do navegador): começa o jeito novo.
  watch(como, novo => {
    zerar();
    passo.value = primeiroPasso(novo);
  });

  // A escolha mostra se a conta já está ligada ao Agger.
  const carregarComeco = async () => {
    comeco.value = COMECO.CARREGANDO;
    try {
      const resposta = await fonte.comeco();
      aggerLigado.value = resposta.aggerLigado;
      renovacoes.value = resposta.renovacoes;
      comeco.value = COMECO.PRONTO;
    } catch {
      comeco.value = COMECO.ERRO;
    }
  };

  const voltar = () => {
    const anterior = passoAnterior(como.value, passo.value);
    erro.value = ERROS.NENHUM;
    if (anterior === PASSOS.COMO) mudarComo('');
    else passo.value = anterior;
  };

  // ---- planilha
  const lerPlanilha = async arquivo => {
    ultimaPlanilha = { arquivo };
    lendo.value = true;
    erro.value = ERROS.NENHUM;
    try {
      leitura.value = await fonte.lerPlanilha(arquivo);
      passo.value = PASSOS.PERGUNTA;
    } catch (falha) {
      erro.value = ERROS_DA_LEITURA[falha?.name] ?? ERROS.LEITURA;
    } finally {
      lendo.value = false;
    }
  };

  const escolherPlanilha = async arquivo => {
    if (!ehPlanilha(arquivo?.name)) {
      erro.value = ERROS.TIPO;
      return;
    }
    await lerPlanilha(arquivo);
  };

  const usarPlanilhaDeExemplo = () => {
    const exemplo = fonte.arquivoDeExemplo();
    return exemplo ? escolherPlanilha(exemplo) : lerPlanilha(null);
  };

  // ---- conferir: a leitura chegou (dos PDFs e do Agger, direto; da planilha,
  // depois da pergunta). Na primeira vez que a conta traz seguros, antes vem a
  // pergunta de onde ficam as renovações.
  const conferir = lida => {
    if (lida) leitura.value = lida;
    erro.value = ERROS.NENHUM;
    passo.value = renovacoes.value.escolhido ? PASSOS.CONFERIR : PASSOS.ONDE;
  };

  // `escolha` nula = seguir sem escolher (quem não pode mexer em funis). A
  // linha do que acontece amanhã cedo passa a usar os dias escolhidos.
  const escolherRenovacoes = async escolha => {
    ocupado.value = true;
    try {
      leitura.value = await fonte.escolherRenovacoes(leitura.value.id, escolha);
      renovacoes.value = { ...renovacoes.value, escolhido: true };
      passo.value = PASSOS.CONFERIR;
    } catch {
      avisar(AVISO_ERRO_SALVAR);
    } finally {
      ocupado.value = false;
    }
  };

  const voltarAPergunta = () => {
    passo.value = PASSOS.PERGUNTA;
  };

  // Escrever na leitura: a fonte devolve a leitura nova.
  const escrever = async gravar => {
    ocupado.value = true;
    try {
      leitura.value = await gravar();
    } catch {
      avisar(AVISO_ERRO_SALVAR);
    } finally {
      ocupado.value = false;
    }
  };
  const guardar = (linha, valor) =>
    escrever(() => fonte.consertar(leitura.value.id, linha, valor));
  const deixarDeFora = linha =>
    escrever(() => fonte.deixarDeFora(leitura.value.id, linha));
  const reabrir = linha =>
    escrever(() => fonte.reabrir(leitura.value.id, linha));
  const trocarDestino = (coluna, destino) =>
    escrever(() => fonte.trocarDestino(leitura.value.id, coluna, destino));

  // ---- trazer e o andamento
  const acompanharATrazida = () => {
    parar();
    vigia = acompanhar({
      intervalo,
      consultar: () => fonte.andamento(trazidaId),
      aoChegar: andamento => {
        porcentagem.value = andamento.porcentagem;
        chegaram.value = {
          seguros: andamento.seguros,
          pessoas: andamento.pessoas,
        };
        if (andamento.situacao === SITUACOES_DA_LISTA.TRAZENDO) return false;
        passo.value = PASSOS.PRONTO;
        return true;
      },
      aoFalhar: () => {
        erro.value = ERROS.ANDAMENTO;
      },
    });
  };

  const trazer = async () => {
    ocupado.value = true;
    erro.value = ERROS.NENHUM;
    try {
      trazidaId = (await fonte.trazer(leitura.value.id)).trazidaId;
    } catch {
      erro.value = ERROS.TRAZER;
      return;
    } finally {
      ocupado.value = false;
    }
    porcentagem.value = 0;
    passo.value = PASSOS.TRAZENDO;
    acompanharATrazida();
  };

  const tentarDeNovo = async () => {
    if (erro.value === ERROS.LEITURA && ultimaPlanilha) {
      await lerPlanilha(ultimaPlanilha.arquivo);
    } else if (erro.value === ERROS.ANDAMENTO) {
      erro.value = ERROS.NENHUM;
      acompanharATrazida();
    }
  };

  // De volta à escolha, do zero (mesmo que o endereço já esteja nela).
  const recomecar = () => {
    zerar();
    passo.value = PASSOS.COMO;
    mudarComo('');
  };

  // "Trazer mais PDFs", "Trazer outra lista": o mesmo jeito, do começo.
  const trazerMais = () => {
    zerar();
    passo.value = primeiroPasso(como.value);
  };

  onScopeDispose(parar);

  return {
    passo,
    etapaDoTopo,
    comeco,
    aggerLigado,
    renovacoes,
    leitura,
    lendo,
    ocupado,
    erro,
    porcentagem,
    chegaram,
    total,
    contadores,
    carregarComeco,
    voltar,
    escolherPlanilha,
    usarPlanilhaDeExemplo,
    conferir,
    escolherRenovacoes,
    voltarAPergunta,
    guardar,
    deixarDeFora,
    reabrir,
    trocarDestino,
    trazer,
    tentarDeNovo,
    recomecar,
    trazerMais,
  };
};
