// #2775 (revisão) — as listas do "Para qual lista?" da folha do Guardar
// lista: todas as páginas (quem tem mais de 25 listas acha todas) e, em cada
// lista, quantas das escolhidas entram nela: as que têm contato e ainda não
// estão lá (o servidor diz quais já estão, already_lead_ids). É esse número
// que o botão "Pôr N empresas na lista" mostra.
// - As páginas vêm por cursor (depois), na ordem do servidor.
// - Se uma página do meio falha, ou se passa do teto, ficam as que já vieram
//   e incompleta avisa a folha ("Nem todas as suas listas apareceram"). Só a
//   falha da primeira página sobe como erro.

// Teto de páginas lidas (25 listas cada), para uma resposta errada do
// servidor não prender a folha num laço.
export const MAX_PAGINAS_DE_LISTAS = 40;

const lerPaginas = async (fonte, empresaIds, depois = null, pagina = 1) => {
  const lida = await fonte.listas({ depois, empresaIds });
  const acabou = !lida.temMais || !lida.listas.length || !lida.depois;
  if (acabou) return { listas: lida.listas, incompleta: false };
  if (pagina >= MAX_PAGINAS_DE_LISTAS) {
    return { listas: lida.listas, incompleta: true };
  }
  let resto;
  try {
    resto = await lerPaginas(fonte, empresaIds, lida.depois, pagina + 1);
  } catch {
    resto = { listas: [], incompleta: true };
  }
  return {
    listas: [...lida.listas, ...resto.listas],
    incompleta: resto.incompleta,
  };
};

export const lerListasDaFolha = async (fonte, escolhidas = []) => {
  const empresaIds = escolhidas
    .filter(empresa => empresa.temContato)
    .map(empresa => empresa.id);
  const { listas, incompleta } = await lerPaginas(fonte, empresaIds);
  return {
    incompleta,
    listas: listas.map(lista => {
      const jaEstao = new Set(lista.jaNaLista || []);
      return {
        ...lista,
        entram: empresaIds.filter(id => !jaEstao.has(id)).length,
      };
    }),
  };
};
