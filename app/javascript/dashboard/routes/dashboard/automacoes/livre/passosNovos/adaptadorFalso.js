// #2414 — o adaptador falso do protótipo dos passos novos (#2931–#2936): o que
// o servidor ainda não responde para os três sem motor (#2931, #2935, #2936):
// os horários livres, o pedido de aprovação e o ensaio. Tudo de exemplo, com
// nomes inventados e sem chamar nada fora da tela. Os de #2932–#2934 já leem o
// servidor (dadosDaConta).
import { galhosDe, todosOsPassos } from '../receita';
import { P, ehPassoNovo, emTeste } from './passosNovos';

const E = `${P}.EXEMPLO`;

// Só os passos novos sem motor ainda levam o ensaio de exemplo: os de #2932–#2934
// passam pelo servidor.
export const temPassoNovo = (passos = []) =>
  todosOsPassos(passos).some(emTeste);

// As pessoas de exemplo (ensaio e histórico).
const NOMES = ['Ana Souza', 'Bruno Lima', 'Carla Dias', 'Diego Rocha'];

// #2935: os 3 próximos horários livres de quem atende.
export const horariosLivres = t => [1, 2, 3].map(n => t(`${E}.HORARIO_${n}`));

// #2931: o card do pedido de aprovação, no formato do CrmKanbanCard.
export const cardDoPedido = t => ({
  id: 9001,
  title: t(`${E}.CARD_TITULO`),
  contact: { id: 9002, name: NOMES[0] },
  value_cents: 480000,
  currency: 'BRL',
  responsible: { type: 'agent', name: NOMES[1] },
});

// O valor de exemplo de um dado no texto do pedido; o de venda só para quem vê
// valores (`podeVerValor`).
const EXEMPLOS = { 'card.valor': 'R$ 4.800,00', 'contato.nome': NOMES[0] };
export const valorDeExemplo = (caminho, podeVerValor, t) => {
  if (caminho === 'card.valor' && !podeVerValor) return t(`${E}.VALOR_OCULTO`);
  return EXEMPLOS[caminho] || null;
};

// #2498 no protótipo — o ensaio com a receita da tela, no formato da API: duas
// conversas de exemplo que entrariam, um nó por passo. O galho fixo (aprovado,
// então, em cada um...) vai com a marca `fixo` e sem nome: o ensaio diz o nome
// do galho, não "Se a IA escolher". Só o caminho do "decidir" leva o nome. O
// passo novo leva `faria: 'passo_novo'`; os de hoje, só a frase.
const ramoDe = (galho, rotuloDoGalho) =>
  galho.ramo.startsWith('caminhos.')
    ? { nome: galho.nome || rotuloDoGalho(galho.ramo) }
    : { fixo: true };
const no = (passo, rotuloDoGalho) => ({
  id: passo.id,
  tipo: passo.tipo,
  faria: ehPassoNovo(passo) ? 'passo_novo' : 'prototipo',
  dados: { passo },
  ramos: galhosDe(passo)
    .filter(galho => (galho.passos || []).length)
    .map(galho => ({
      chave: galho.ramo,
      ...ramoDe(galho, rotuloDoGalho),
      passos: galho.passos.map(dentro => no(dentro, rotuloDoGalho)),
    })),
});

const HORA = 60 * 60 * 1000;
export const ensaiarComPassosNovos = (receita, rotuloDoGalho) => {
  const passos = (receita?.passos || []).map(passo => no(passo, rotuloDoGalho));
  const conversa = (n, nome) => ({
    conversa_id: 900 + n,
    nome,
    entraria: true,
    ultima_atividade: new Date(Date.now() - n * HORA).toISOString(),
    passos,
  });
  return Promise.resolve({
    data: { conversas: [conversa(1, NOMES[0]), conversa(2, NOMES[1])] },
  });
};

export const NOMES_DE_EXEMPLO = NOMES;
