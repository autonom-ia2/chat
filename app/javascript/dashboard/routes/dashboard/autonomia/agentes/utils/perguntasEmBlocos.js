// #3020 — as perguntas de um agente pronto por ramo, em blocos. A lista é a do servidor: [{ id, texto, tirada }] e, na
// pergunta que veio do modelo em blocos, o lugar dela: `bloco` (o nome do bloco), `se` (a condição, "houver
// elevadores") e `segue` (depende da pergunta de cima). Pergunta sem `bloco` é a que o dono escreveu.
// Ligada é o contrário de `tirada`. Nada aqui muda a lista que recebe: toda função devolve uma lista nova.

export const temBlocos = itens => itens.some(item => item.bloco);

export const ligada = item => !item.tirada;

// As perguntas que o dono escreveu (sem bloco), na ordem.
export const soltas = itens => itens.filter(item => !item.bloco);

// [{ nome, perguntas }] na ordem em que cada bloco aparece na lista.
export const blocosDe = itens =>
  itens
    .filter(item => item.bloco)
    .reduce((blocos, item) => {
      const bloco = blocos.find(outro => outro.nome === item.bloco);
      if (!bloco) return [...blocos, { nome: item.bloco, perguntas: [item] }];
      return blocos.map(outro =>
        outro === bloco
          ? { ...outro, perguntas: [...outro.perguntas, item] }
          : outro
      );
    }, []);

// Quantas estão ligadas: as que todo cliente responde e as que só aparecem conforme a resposta (têm condição).
export const contar = itens => {
  const ligadas = itens.filter(ligada);
  const conforme = ligadas.filter(item => item.se).length;
  return {
    ligadas: ligadas.length,
    todos: ligadas.length - conforme,
    conforme,
    total: itens.length,
  };
};

// A pergunta de cima de quem `segue`: a anterior mais próxima, no mesmo bloco, que não segue ninguém.
const maeDe = (itens, indice) => {
  const item = itens[indice];
  if (!item.segue) return null;
  return (
    itens
      .slice(0, indice)
      .reverse()
      .find(outro => outro.bloco === item.bloco && !outro.segue) || null
  );
};

// As que seguem a pergunta do `indice`: as seguintes do mesmo bloco, até a próxima que não segue ninguém.
const filhasDe = (itens, indice) => {
  const item = itens[indice];
  if (item.segue) return [];
  const depois = itens.slice(indice + 1);
  const fim = depois.findIndex(
    outro => outro.bloco !== item.bloco || !outro.segue
  );
  return fim === -1 ? depois : depois.slice(0, fim);
};

// Liga ou desliga uma pergunta. Desligar a de cima desliga as que seguem; ligar uma que segue liga a de cima junto.
export const alternarPergunta = (itens, id) => {
  const indice = itens.findIndex(item => item.id === id);
  if (indice === -1) return itens;
  const ligar = itens[indice].tirada;
  const junto = ligar
    ? [maeDe(itens, indice)].filter(Boolean)
    : filhasDe(itens, indice);
  const ids = [id, ...junto.map(item => item.id)];
  return itens.map(item =>
    ids.includes(item.id) ? { ...item, tirada: !ligar } : item
  );
};

// O que ligou ou desligou de `antes` para `depois`: { id: tirada }.
export const toquesEntre = (antes, depois) => {
  const eram = new Map(antes.map(item => [item.id, item.tirada]));
  return Object.fromEntries(
    depois
      .filter(item => eram.get(item.id) !== item.tirada)
      .map(item => [item.id, item.tirada])
  );
};

// A lista com os toques ({ id: tirada }) por cima. O resto de cada item fica como a lista trouxe.
export const comToques = (itens, toques) =>
  itens.map(item =>
    item.id in toques ? { ...item, tirada: toques[item.id] } : item
  );

// Liga ou desliga todas as perguntas de um bloco.
export const mudarBloco = (itens, nome, ligar) =>
  itens.map(item => (item.bloco === nome ? { ...item, tirada: !ligar } : item));
