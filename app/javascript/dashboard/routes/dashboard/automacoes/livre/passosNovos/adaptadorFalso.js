// #2414 — o adaptador falso do protótipo dos passos novos (#2931–#2936): o que
// o servidor ainda não responde. Os blocos da conta, as integrações ligadas, a
// resposta de um teste, os horários livres, a contagem da lista, o pedido de
// aprovação e o ensaio. Tudo de exemplo, com nomes inventados e sem chamar
// nada fora da tela. A implementação troca cada função pela rota de verdade.
import { galhosDe, todosOsPassos } from '../receita';
import { P, ehPassoNovo, emTeste, listaPronta } from './passosNovos';

const E = `${P}.EXEMPLO`;

// Só os passos que ainda não salvam (#2932–#2934) fazem o ensaio de exemplo; a
// aprovação, a reunião e a pesquisa vão ao ensaio de verdade.
export const temPassoNovo = (passos = []) =>
  todosOsPassos(passos).some(emTeste);

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
// O nome de cada dado em palavras do dia a dia ("Status do pedido"), que vira o
// nome inicial do dado guardado. A implementação precisa do mesmo: um rótulo
// legível, sugerido pela integração ou pela IA, nunca a chave crua do JSON.
const ROTULOS = {
  'pedido.numero': 'NUMERO_DO_PEDIDO',
  'pedido.status': 'STATUS_DO_PEDIDO',
  'pedido.previsao': 'PREVISAO_DE_ENTREGA',
  'cliente.nome': 'NOME_DO_CLIENTE',
  'endereco.rua': 'RUA',
  'endereco.bairro': 'BAIRRO',
  'endereco.cidade': 'CIDADE',
  'endereco.estado': 'ESTADO',
  'boleto.situacao': 'SITUACAO_DO_BOLETO',
  'boleto.vencimento': 'VENCIMENTO_DO_BOLETO',
  'boleto.valor': 'VALOR_DO_BOLETO',
};
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
// o nome em palavras ("pedido.status" vira "Status do pedido") e o valor.
const achatar = (objeto, t, antes = '') =>
  Object.entries(objeto).flatMap(([chave, valor]) => {
    const caminho = antes ? `${antes}.${chave}` : chave;
    if (valor && typeof valor === 'object') return achatar(valor, t, caminho);
    const nome = t(`${E}.DADOS.${ROTULOS[caminho]}`);
    return [{ caminho, nome, valor: traduzir(valor, t) }];
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
// #2934: a busca do ensaio, só depois do OK de quem ensaia: cada dado guardado
// com o valor (aqui, o do teste).
export const buscarNoEnsaio = (passo, t) =>
  Promise.resolve(
    (passo.guardar || []).map(dado => ({
      nome: dado.nome,
      valor: valorDeTeste(passo.fonte, dado.caminho, t),
    }))
  );

// #2935: os 3 próximos horários livres de quem atende.
export const horariosLivres = t => [1, 2, 3].map(n => t(`${E}.HORARIO_${n}`));

// #2932: os públicos de exemplo da conta, para a lista.
const PUBLICOS = [
  { id: 1, chave: 'CLIENTES_ATIVOS' },
  { id: 2, chave: 'SEM_COMPRA' },
];
export const publicosDaConta = t =>
  PUBLICOS.map(publico => ({
    value: publico.id,
    label: t(`${E}.PUBLICOS.${publico.chave}`),
  }));
export const nomeDoPublico = (id, t) =>
  publicosDaConta(t).find(publico => publico.value === id)?.label || '';

// #2932: o que uma rodada já feita encontrou (o histórico de exemplo).
export const rodadaDaLista = () => ({
  total: TOTAL_DA_LISTA,
  primeiros: NOMES.slice(0, 3),
});
// Quantos entrariam hoje e os 3 primeiros. A lista de verdade respeita o
// alcance de quem ligou, o teto, bloqueados e descadastrados.
export const contarItens = lista =>
  listaPronta(lista) ? rodadaDaLista() : { total: 0, primeiros: [] };

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
