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
