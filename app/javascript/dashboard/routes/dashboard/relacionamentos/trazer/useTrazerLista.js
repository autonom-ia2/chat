import { onScopeDispose } from 'vue';
import { INTERVALO_INICIAL_MS } from './consultaComRecuo';
import {
  criarEstado,
  criarMemoria,
  derivadosDoEstado,
  usePassosDaTela,
  useRecomeco,
} from './estadoDoTrazer';
import { ERROS } from './falhasDaTela';
import {
  useColunasDaLeitura,
  useEscritaNaLeitura,
  useLinhasDaLeitura,
  useMaisProblemas,
} from './useEscritasNaLeitura';
import {
  useChegadaDaLeitura,
  useEnvioDaPlanilha,
  useReleitura,
} from './useLeituraDaPlanilha';
import {
  usePedidoDosValores,
  usePerguntasDaLista,
} from './usePerguntasDaLista';
import {
  useAndamentoDaTela,
  useTentarDeNovo,
  useTrazerAgora,
} from './useTrazerAgora';

// #2894 — o estado de "Trazer minha lista": a etapa, a leitura da planilha, as
// respostas e o andamento. Fala só com a fonte (fonte/trazerFonte.js); quem
// desenha é a página.
// #2896 — quem o servidor recusa por falta de acesso liga `semAcesso` (a tela
// diz isso em vez de oferecer "tentar de novo"). A lista que para no meio não é
// "Pronto": a tela avisa e chama `aoFalhar`.
// Fatia 2 — quantas pessoas entram (`entram`) e os números do topo vêm da
// leitura que o servidor manda; a tela não refaz a conta. Cada escrita tem
// lugar próprio para dizer que não deu certo, sempre como frase fixa:
//   - a linha: `recusaDoConserto` (`{ linha, motivo }`), dita no cartão dela;
//   - a coluna: `recusaDaColuna` (`{ coluna, chave }`), dita na linha da coluna;
//   - a pergunta: `recusaDaPergunta` (`{ chave }`), dita na pergunta;
//   - o trazer: `erro` (e, quando falta dizer quais valores da coluna querem
//     dizer cliente, a própria pergunta: `recusaDaPergunta`).
// Quando a escrita faz o servidor ler a planilha de novo, a mudança já está
// salva: a tela fica `relendo` até a leitura voltar e, se a espera falha, fica
// em `releituraParada` (o "tentar de novo" só pergunta de novo, nunca repete a
// escrita). A releitura que não sobra ninguém volta ao Enviar. O pedido que o
// servidor já não conhece (outra aba ou outra pessoa mexeu) faz a tela ler a
// leitura de novo sozinha e dizer que a lista mudou (`mudou`). A conferência
// que venceu (a planilha já foi apagada do servidor) volta ao Enviar, venha a
// notícia de uma escrita, do trazer ou de quem pergunta pela leitura.
// Depois de cada escrita a tela fica com as perguntas e as respostas que a
// leitura traz: a troca de uma coluna pode tirar a pergunta do telefone ou
// fazer uma resposta deixar de valer. A resposta velha não fica guardada, e a
// troca que deixa uma pergunta sem resposta leva a pessoa de volta a ela
// (`perguntaDeNovo`).
// O estado e a memória estão em trazer/estadoDoTrazer.js; cada assunto é uma
// parte com nome: a leitura (trazer/useLeituraDaPlanilha.js), as escritas
// (trazer/useEscritasNaLeitura.js), as perguntas (trazer/usePerguntasDaLista.js)
// e o trazer (trazer/useTrazerAgora.js). Aqui elas só são montadas.
export { ERROS };
export const INTERVALO_DO_ANDAMENTO_MS = INTERVALO_INICIAL_MS;

// Na ordem: cada parte recebe a tela com tudo o que as anteriores entregaram.
const PARTES = [
  usePassosDaTela,
  useAndamentoDaTela,
  useRecomeco,
  useChegadaDaLeitura,
  useEnvioDaPlanilha,
  useReleitura,
  useEscritaNaLeitura,
  useLinhasDaLeitura,
  useColunasDaLeitura,
  useMaisProblemas,
  usePerguntasDaLista,
  usePedidoDosValores,
  useTrazerAgora,
  useTentarDeNovo,
];

const montar = inicio =>
  PARTES.reduce((tela, parte) => ({ ...tela, ...parte(tela) }), inicio);

// O que a página pode pedir à tela.
const acoesDaPagina = tela => ({
  escolherArquivo: tela.escolherArquivo,
  usarExemplo: tela.usarExemplo,
  retomar: tela.retomar,
  responder: tela.responder,
  escolherColunaDeCliente: tela.escolherColunaDeCliente,
  continuar: tela.continuar,
  voltar: tela.voltar,
  guardar: tela.guardar,
  deixarDeFora: tela.deixarDeFora,
  reabrir: tela.reabrir,
  trocarDestino: tela.trocarDestino,
  mostrarMais: tela.mostrarMais,
  trazer: tela.trazer,
  tentarDeNovo: tela.tentarDeNovo,
  recomecar: tela.recomecar,
});

export const useTrazerLista = ({
  fonte,
  avisar = () => {},
  aoFalhar = () => {},
  intervalo = INTERVALO_DO_ANDAMENTO_MS,
}) => {
  const estadoDaTela = criarEstado();
  const memoria = criarMemoria();
  const tela = montar({
    ...estadoDaTela,
    memoria,
    fonte,
    avisar,
    aoFalhar,
    intervalo,
  });

  onScopeDispose(() => {
    memoria.encerrado = true;
    tela.andamento.encerrar();
    // A fonte real pode estar esperando a leitura da planilha: para de perguntar.
    fonte.encerrar?.();
  });

  return {
    ...estadoDaTela,
    ...derivadosDoEstado(estadoDaTela, memoria),
    porcentagem: tela.andamento.porcentagem,
    novasTrazidas: tela.andamento.novas,
    completadasTrazidas: tela.andamento.completadas,
    ...acoesDaPagina(tela),
  };
};
