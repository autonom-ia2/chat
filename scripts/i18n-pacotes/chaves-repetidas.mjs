/* eslint-disable no-continue -- leitura caractere a caractere: pular a string já lida é o caminho natural */
// #2858 — chave repetida no mesmo objeto de um catálogo i18n. O JSON.parse aceita e fica com a última, apagando a
// primeira em silêncio (no merge da F7 com a F5, `AGENTS.VITRINE.CAMPOS.POR_TIPO` das placas solares virou "Tipos de
// crime"). Aqui o texto é lido caractere a caractere, sem regex: em cada objeto aberto, a string que vem depois de
// "{" ou de "," é uma chave; a que já apareceu naquele objeto é repetida. Devolve o caminho de cada uma
// ("AGENTS.VITRINE.CAMPOS.POR_TIPO"). O arquivo precisa ser JSON válido: quem confere isso é o JSON.parse do checador.

// A string que começa em `inicio` (nas aspas) -> [o texto dela, a posição depois das aspas de fechamento].
const lerString = (texto, inicio) => {
  let fim = inicio + 1;
  while (fim < texto.length && texto[fim] !== '"') {
    fim += texto[fim] === '\\' ? 2 : 1;
  }
  return [JSON.parse(texto.slice(inicio, fim + 1)), fim + 1];
};

const caminhoDoFilho = pai => {
  if (!pai) return '';
  return pai.tipo === 'objeto' ? pai.chaveAtual : pai.caminho;
};

export const chavesRepetidas = texto => {
  const pilha = [];
  const repetidas = [];
  let posicao = 0;
  while (posicao < texto.length) {
    const caractere = texto[posicao];
    const topo = pilha.at(-1);
    if (caractere === '"') {
      const [valor, depois] = lerString(texto, posicao);
      posicao = depois;
      if (topo?.tipo !== 'objeto' || !topo.esperaChave) continue;
      const caminho = topo.caminho ? `${topo.caminho}.${valor}` : valor;
      if (topo.chaves.has(valor)) repetidas.push(caminho);
      topo.chaves.add(valor);
      topo.chaveAtual = caminho;
      topo.esperaChave = false;
      continue;
    }
    if (caractere === '{') {
      pilha.push({
        tipo: 'objeto',
        caminho: caminhoDoFilho(topo),
        chaves: new Set(),
        esperaChave: true,
      });
    } else if (caractere === '[') {
      pilha.push({ tipo: 'lista', caminho: caminhoDoFilho(topo) });
    } else if (caractere === '}' || caractere === ']') {
      pilha.pop();
    } else if (caractere === ',' && topo?.tipo === 'objeto') {
      topo.esperaChave = true;
    }
    posicao += 1;
  }
  return repetidas;
};
