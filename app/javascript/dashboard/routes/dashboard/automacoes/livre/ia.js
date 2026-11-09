// #2500 F7 — os caminhos do "decidir". O caminho mostra o nome que a pessoa
// escreveu ("Cotação"); a chave, que a IA devolve e que nunca aparece na tela,
// sai dele: minúscula, sem acento, com _. As mesmas regras a Receita confere
// no servidor (caminho_repetido, caminho_reservado, caminho_sem_letra).
const LETRAS = 'abcdefghijklmnopqrstuvwxyz';
const DIGITOS = '0123456789';
// A chave do ramo "nenhum se aplica" (Receita::NENHUM).
const NENHUM = 'nenhum';

export const chaveDoNome = nome =>
  [...nome.normalize('NFD').toLowerCase()]
    .filter(
      letra =>
        LETRAS.includes(letra) || DIGITOS.includes(letra) || letra === ' '
    )
    .join('')
    .split(' ')
    .filter(Boolean)
    .join('_');

const nomeComparavel = caminho => (caminho.nome || '').trim().toLowerCase();

// O que impede o caminho de ser salvo, em uma palavra para o i18n; null quando
// está certo. Sem nome ainda não é problema: o painel só pede o nome.
export const problemaDoCaminho = (caminhos, indice) => {
  const caminho = caminhos[indice];
  if (!nomeComparavel(caminho)) return null;
  if (![...(caminho.chave || '')].some(letra => LETRAS.includes(letra)))
    return 'SEM_LETRA';
  if (caminho.chave === NENHUM) return 'RESERVADO';
  const repetido = caminhos.some(
    (outro, i) =>
      i !== indice &&
      (outro.chave === caminho.chave ||
        nomeComparavel(outro) === nomeComparavel(caminho))
  );
  return repetido ? 'REPETIDO' : null;
};

export const caminhosProntos = caminhos =>
  caminhos.length >= 2 &&
  caminhos.every(
    (caminho, indice) =>
      nomeComparavel(caminho) &&
      caminho.descricao?.trim() &&
      !problemaDoCaminho(caminhos, indice)
  );

// #2414 G31 — o "decidir" que espera a próxima resposta e decide de novo
// quando a IA escolhe um dos caminhos marcados. As mesmas regras a Receita
// confere no servidor (DecidirDeNovo): o caminho marcado não tem passos, e
// sobra pelo menos um caminho para a automação seguir.
export { NENHUM };

// Os nomes dos caminhos marcados que ainda têm passos ("nenhum" pelo galho
// dele), na ordem em que aparecem.
export const marcadosComPassos = passo => {
  const marcados = passo.de_novo?.caminhos || [];
  const cheios = (passo.caminhos || [])
    .filter(caminho => marcados.includes(caminho.chave))
    .filter(caminho => (caminho.passos || []).length)
    .map(caminho => caminho.nome);
  return marcados.includes(NENHUM) && (passo.nenhum || []).length
    ? [...cheios, NENHUM]
    : cheios;
};

// A chave marcada que o passo não tem mais (o caminho foi renomeado ou tirado).
export const marcadosDesconhecidos = passo => {
  const chaves = [...(passo.caminhos || []).map(item => item.chave), NENHUM];
  return (passo.de_novo?.caminhos || []).filter(
    chave => !chaves.includes(chave)
  );
};

export const todosMarcados = passo =>
  (passo.caminhos || []).length > 0 &&
  (passo.caminhos || []).every(caminho =>
    (passo.de_novo?.caminhos || []).includes(caminho.chave)
  );

// Desligado (sem `de_novo`) está pronto; ligado, pede um caminho marcado, o
// prazo e nenhum dos dois problemas acima.
export const deNovoPronto = passo => {
  const deNovo = passo.de_novo;
  if (!deNovo) return true;
  return (
    (deNovo.caminhos || []).length > 0 &&
    Number.isInteger(deNovo.prazo?.valor) &&
    Boolean(deNovo.prazo?.unidade) &&
    !marcadosDesconhecidos(passo).length &&
    !marcadosComPassos(passo).length &&
    !todosMarcados(passo)
  );
};
