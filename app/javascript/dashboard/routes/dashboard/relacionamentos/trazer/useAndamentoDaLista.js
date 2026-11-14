import { ref } from 'vue';
import { agendaComRecuo } from './consultaComRecuo';
import { SITUACOES_DA_LISTA } from './prazo';

// #2896 — o andamento da lista que acabou de ser trazida: a tela pergunta de
// novo ao servidor até a lista terminar, com a espera crescendo e sem perguntar
// com a aba escondida (trazer/consultaComRecuo.js). Há uma cadeia de consultas
// por vez: começar outra, ou parar, sobe a geração, e a resposta que volta de
// uma geração velha é descartada em vez de mexer no estado.
// `aoTerminar`, `aoParar` (a lista parou no meio) e `aoFalhar` (a consulta deu
// erro; recebe a falha) são de quem usa.

// O que fazer com a situação que a consulta trouxe: a lista parou no meio,
// terminou, ou ainda está sendo trazida (`continuar` pergunta de novo).
const seguirASituacao = (situacao, { aoParar, aoTerminar, continuar }) => {
  if (situacao === SITUACOES_DA_LISTA.FALHOU) aoParar();
  else if (situacao !== SITUACOES_DA_LISTA.TRAZENDO) aoTerminar();
  else continuar();
};

export const useAndamentoDaLista = opcoes => {
  const { fonte, intervalo, aoTerminar, aoParar, aoFalhar } = opcoes;
  const numeros = { porcentagem: ref(0), novas: ref(0), completadas: ref(0) };
  const agenda = agendaComRecuo({ inicial: intervalo });
  let geracao = 0;
  let encerrado = false;
  let trazidaId = null;

  const vale = minha => !encerrado && minha === geracao;

  const consultar = async minha => {
    if (!vale(minha)) return;
    try {
      const andamento = await fonte.andamento(trazidaId);
      if (!vale(minha)) return;
      numeros.porcentagem.value = andamento.porcentagem;
      numeros.novas.value = andamento.novas;
      numeros.completadas.value = andamento.completadas;
      const continuar = () => agenda.agendar(() => consultar(minha));
      seguirASituacao(andamento.situacao, { aoParar, aoTerminar, continuar });
    } catch (falha) {
      if (vale(minha)) aoFalhar(falha);
    }
  };

  // Para de perguntar: a cadeia que estiver em voo deixa de valer.
  const parar = () => {
    geracao += 1;
    agenda.recomecar();
    return geracao;
  };

  // Acompanha a lista `id` do começo, numa cadeia nova.
  const acompanhar = id => {
    trazidaId = id;
    numeros.porcentagem.value = 0;
    return consultar(parar());
  };

  // A consulta deu erro e a pessoa pediu de novo: a mesma lista, cadeia nova.
  const consultarDeNovo = () => consultar(parar());

  const encerrar = () => {
    encerrado = true;
    parar();
  };

  const acoes = { acompanhar, consultarDeNovo, parar, encerrar };
  return { ...numeros, ...acoes, geracao: () => geracao };
};
