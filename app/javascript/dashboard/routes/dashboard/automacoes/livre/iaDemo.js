// #2500 F7 — PROTÓTIPO. Adaptador falso do "Testar este passo" e do custo médio
// do passo, até existir a rota de verdade (POST automacoes/testar_passo, que usa
// o mesmo PassoDeIa do executor). Os textos são exemplos fixos; nada vai à IA.
const CUSTO_MEDIO = {
  decidir: 0.0002,
  extrair: 0.0003,
  escrever: 0.0006,
  resumir: 0.0005,
};

export const custoMedio = tipo => CUSTO_MEDIO[tipo] ?? null;

const CONVERSAS = [
  { id: 1042, cliente: 'bati o carro ontem, e agora? placa ABC1D23' },
  { id: 1038, cliente: 'quanto fica o seguro de um Onix 2022?' },
  { id: 1031, cliente: 'oi, bom dia' },
];

const resultado = (passo, conversa, indice) => {
  if (passo.tipo === 'decidir') {
    const chaves = (passo.caminhos || []).map(caminho => caminho.chave);
    const caminho =
      indice < chaves.length && indice < 2 ? chaves[indice] : null;
    return {
      caminho,
      motivo: caminho
        ? `O cliente escreveu: “${conversa.cliente}”.`
        : 'A mensagem só cumprimenta; não dá para saber o assunto.',
    };
  }
  if (passo.tipo === 'escrever')
    return {
      texto:
        'Oi! Recebemos sua mensagem e um corretor responde em até 1 hora. Obrigado pela paciência.',
    };
  return {
    texto:
      'Cliente relata batida ontem.\nInformou a placa ABC1D23.\nPede orientação sobre o sinistro.',
  };
};

export const testarPasso = passo =>
  new Promise(resolve => {
    setTimeout(
      () =>
        resolve({
          custo: (custoMedio(passo.tipo) || 0) * CONVERSAS.length,
          conversas: CONVERSAS.map((conversa, indice) => ({
            id: conversa.id,
            ...resultado(passo, conversa, indice),
          })),
        }),
      600
    );
  });
