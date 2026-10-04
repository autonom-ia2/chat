// Atalhos da tela inicial: o rótulo é o jeito como a pessoa fala do problema, e o artigo é o que resolve.
// Os ids vêm de docs/central-de-ajuda/mapa-de-artigos.json; a escolha de cada destino é feita aqui.
// Um problema aparece numa lista só: "a conversa travou" é sintoma (08.06 cobre todos os bloqueios,
// inclusive o de 24 horas), e o chip leva direto ao conceito da janela (18.01) com o nome dele.
// "Número bloqueado" leva ao 18.02, cujo "O que dá errado" diz o que fazer quando a Meta derruba o número.
export const MAIS_PROCURADOS = [
  { rotulo: 'WHATSAPP', artigo: '07.01' },
  { rotulo: 'JANELA_24H', artigo: '18.01' },
  { rotulo: 'FUNIL', artigo: '10.01' },
  { rotulo: 'CONVIDAR', artigo: '04.02' },
  { rotulo: 'DISPARO', artigo: '18.02' },
];

export const SINTOMAS = [
  { rotulo: 'CONVERSA_TRAVOU', artigo: '08.06' },
  { rotulo: 'NUMERO_BLOQUEADO', artigo: '18.02' },
  { rotulo: 'IA_GASTANDO', artigo: '18.03' },
  { rotulo: 'CSAT_VAZIO', artigo: '07.11' },
];

// O `ref` do artigo é o id com hífen: 02.06 → 02-06.
export const refDoArtigo = id => String(id).replaceAll('.', '-');

// Os ids que a API devolveu para a conta: o servidor já tirou o que o papel ou os recursos da conta
// não liberam, e um link para artigo escondido daria em "não encontrado".
export const idsVisiveis = capitulos =>
  new Set(
    capitulos.flatMap(capitulo =>
      (capitulo.artigos || []).map(artigo => artigo.id)
    )
  );

// Só o atalho cujo artigo veio para a conta.
export const atalhosVisiveis = (atalhos, capitulos) => {
  const ids = idsVisiveis(capitulos);
  return atalhos
    .filter(atalho => ids.has(atalho.artigo))
    .map(atalho => ({ ...atalho, ref: refDoArtigo(atalho.artigo) }));
};
