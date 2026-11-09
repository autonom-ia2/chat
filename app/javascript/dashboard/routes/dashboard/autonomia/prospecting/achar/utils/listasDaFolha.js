// #2775 (revisão) — as listas do "Para qual lista?" da folha do Guardar
// lista: todas as páginas (quem tem mais de 25 listas acha todas) e, em cada
// lista, quantas das escolhidas entram nela: as que têm contato e ainda não
// estão lá (o servidor diz quais já estão, already_lead_ids). É esse número
// que o botão "Pôr N empresas na lista" mostra.

// Teto de páginas lidas (25 listas cada), para uma resposta errada do
// servidor não prender a folha num laço.
export const MAX_PAGINAS_DE_LISTAS = 40;

const lerPaginas = async (fonte, empresaIds, pagina = 1) => {
  const { listas, temMais } = await fonte.listas(pagina, { empresaIds });
  if (!temMais || !listas.length || pagina >= MAX_PAGINAS_DE_LISTAS) {
    return listas;
  }
  return [...listas, ...(await lerPaginas(fonte, empresaIds, pagina + 1))];
};

export const lerListasDaFolha = async (fonte, escolhidas = []) => {
  const empresaIds = escolhidas
    .filter(empresa => empresa.temContato)
    .map(empresa => empresa.id);
  const listas = await lerPaginas(fonte, empresaIds);
  return listas.map(lista => {
    const jaEstao = new Set(lista.jaNaLista || []);
    return {
      ...lista,
      entram: empresaIds.filter(id => !jaEstao.has(id)).length,
    };
  });
};
