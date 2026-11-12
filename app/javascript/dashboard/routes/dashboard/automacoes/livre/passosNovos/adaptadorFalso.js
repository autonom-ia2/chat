// #2414 — o adaptador falso do protótipo dos passos novos (#2931–#2936): o que
// o servidor ainda não responde. Os blocos da conta, as integrações ligadas, a
// resposta de um teste, os horários livres, a contagem da lista, o pedido de
// aprovação e o ensaio. Tudo de exemplo, com nomes inventados e sem chamar
// nada fora da tela. A implementação troca cada função pela rota de verdade.
import { galhosDe, todosOsPassos } from '../receita';
import { P, ehPassoNovo } from './passosNovos';

const E = `${P}.EXEMPLO`;

export const temPassoNovo = (passos = []) =>
  todosOsPassos(passos).some(ehPassoNovo);

// As pessoas da lista de exemplo (contagem, ensaio e histórico).
const NOMES = ['Ana Souza', 'Bruno Lima', 'Carla Dias', 'Diego Rocha'];
const TOTAL_DA_LISTA = 12;

// #2933: os blocos da conta (automações sem gatilho próprio), cada um com o
// que faz em uma frase e os passos de dentro.
const BLOCOS = [
  { id: 1, chave: 'BOAS_VINDAS', passos: 3 },
  { id: 2, chave: 'LEMBRAR', passos: 2 },
  { id: 3, chave: 'DOCUMENTO', passos: 2 },
];
const passosDoBloco = (bloco, t) =>
  Array.from({ length: bloco.passos }, (_, i) =>
    t(`${E}.BLOCOS.${bloco.chave}.PASSO_${i + 1}`)
  );
export const blocosDaConta = t =>
  BLOCOS.map(bloco => ({
    id: bloco.id,
    nome: t(`${E}.BLOCOS.${bloco.chave}.NOME`),
    frase: t(`${E}.BLOCOS.${bloco.chave}.FRASE`),
    passos: passosDoBloco(bloco, t),
  }));
export const blocoDe = (id, t) =>
  blocosDaConta(t).find(bloco => bloco.id === id) || null;

// #2934: as integrações já conectadas e a resposta de um teste de cada uma.
const INTEGRACOES = [
  {
    id: 'loja',
    resposta: {
      pedido: { numero: '10482', status: 'STATUS', previsao: '18/11' },
      cliente: { nome: NOMES[0] },
    },
  },
  {
    id: 'cep',
    resposta: {
      endereco: {
        rua: 'Rua das Flores',
        bairro: 'Centro',
        cidade: 'Campinas',
        estado: 'SP',
      },
    },
  },
  {
    id: 'boletos',
    resposta: {
      boleto: { situacao: 'SITUACAO', vencimento: '10/11', valor: 'R$ 189,90' },
    },
  },
];
const CODIGOS = { STATUS: 'STATUS_ENVIADO', SITUACAO: 'SITUACAO_PAGO' };
const traduzir = (valor, t) =>
  CODIGOS[valor] ? t(`${E}.${CODIGOS[valor]}`) : valor;
export const integracoesDaConta = t =>
  INTEGRACOES.map(item => ({
    value: item.id,
    label: t(`${E}.INTEGRACOES.${item.id.toUpperCase()}`),
  }));
export const nomeDaIntegracao = (id, t) =>
  integracoesDaConta(t).find(item => item.value === id)?.label || '';

// A resposta vira a lista de dados que a pessoa toca: o caminho (para guardar),
// o nome em palavras ("pedido.status" vira "pedido status") e o valor. Sem
// expressão regular: Object.entries e split.
const emPalavras = caminho => caminho.split('.').join(' ').split('_').join(' ');
const achatar = (objeto, t, antes = '') =>
  Object.entries(objeto).flatMap(([chave, valor]) => {
    const caminho = antes ? `${antes}.${chave}` : chave;
    if (valor && typeof valor === 'object') return achatar(valor, t, caminho);
    return [{ caminho, nome: emPalavras(caminho), valor: traduzir(valor, t) }];
  });

// O endereço próprio responde como a loja: é só a forma da tela.
const dadosDoTeste = (fonte, t) => {
  const id = fonte?.de === 'endereco' ? 'loja' : fonte?.id;
  const item = INTEGRACOES.find(integracao => integracao.id === id);
  return item ? achatar(item.resposta, t) : [];
};
export const testarConsulta = (fonte, t) =>
  Promise.resolve(dadosDoTeste(fonte, t));
export const valorDeTeste = (fonte, caminho, t) =>
  dadosDoTeste(fonte, t).find(dado => dado.caminho === caminho)?.valor || '';

// #2935: os 3 próximos horários livres de quem atende.
export const horariosLivres = t => [1, 2, 3].map(n => t(`${E}.HORARIO_${n}`));

// #2932: o que uma rodada já feita encontrou (o histórico de exemplo).
export const rodadaDaLista = () => ({
  total: TOTAL_DA_LISTA,
  primeiros: NOMES.slice(0, 3),
});
// Quantos entrariam hoje e os 3 primeiros. A lista de verdade respeita o
// alcance de quem ligou, o teto, bloqueados e descadastrados.
const listaEscolhida = lista =>
  lista?.de === 'etapa'
    ? Number.isInteger(lista.etapa_id)
    : Boolean(lista?.etiqueta);
export const contarItens = lista =>
  listaEscolhida(lista) ? rodadaDaLista() : { total: 0, primeiros: [] };

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
// conversas de exemplo que entrariam, um nó por passo, os galhos com o nome. O
// passo novo leva `faria: 'passo_novo'`; os de hoje, só a frase.
const no = (passo, rotuloDoGalho) => ({
  id: passo.id,
  tipo: passo.tipo,
  faria: ehPassoNovo(passo) ? 'passo_novo' : 'prototipo',
  dados: { passo },
  ramos: galhosDe(passo)
    .filter(galho => (galho.passos || []).length)
    .map(galho => ({
      chave: galho.ramo,
      nome: galho.nome || rotuloDoGalho(galho.ramo),
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
