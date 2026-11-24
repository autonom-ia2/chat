// #3098 — a frase que compara quem recebeu a campanha com o grupo de controle (quem ficou sem receber), pela taxa de
// compra de cada lado. Funções puras.
//
// A frase é calculada com os mesmos números redondos que a tela mostra ("De cada 100 que receberam, 5 compraram"),
// não com a taxa real: se a tela diz 5 e 2, a frase não pode dizer "2,6 vezes". E diz em palavras ("o dobro",
// "o triplo"), sempre arredondando para baixo; só a partir de 4 vezes vira número inteiro.

// Abaixo disso, o grupo de controle é pequeno demais para a diferença dizer alguma coisa.
export const MINIMO_NO_CONTROLE = 30;
// Se quem ficou sem receber comprasse no mesmo ritmo de quem recebeu, quantas compras teria. Abaixo disso, uma ou
// duas compras a mais ou a menos viram "o dobro" ou "comprou menos": ainda é sorte, não resultado.
const MINIMO_DE_COMPRAS_ESPERADAS = 5;
// Diferença de até 15% para cima ou para baixo é "compraram quase igual".
const QUASE_IGUAL = 1.15;
const DOBRO = 2;
const TRIPLO = 3;
const DIZ_AS_VEZES = 4;

const taxa = (compraram, total) => (total > 0 ? compraram / total : 0);

// "De cada N": 100, ou 1.000 quando algum lado comprou menos de 1 em 100 (senão vira "0 compraram").
const porEscala = (lado, escala) => {
  const n = Math.round(taxa(lado.compraram, lado.pessoas) * escala);
  return lado.compraram > 0 ? Math.max(1, n) : 0;
};

// `receberam` e `controle`: { pessoas, compraram }. Devolve { escala, receberam, controle } com quantos compram
// de cada `escala` pessoas em cada lado, em inteiros.
export const emGente = (receberam, controle) => {
  const precisaDeMil = [receberam, controle].some(
    lado => lado.compraram > 0 && taxa(lado.compraram, lado.pessoas) * 100 < 1
  );
  const escala = precisaDeMil ? 1000 : 100;
  return {
    escala,
    receberam: porEscala(receberam, escala),
    controle: porEscala(controle, escala),
  };
};

// #3099: também usada para comparar as duas versões da mensagem (vencedora.js), com a mesma régua de palavras.
export const pelaDiferenca = vezes => {
  if (vezes >= DIZ_AS_VEZES) return { chave: 'MAIS', vezes: Math.floor(vezes) };
  if (vezes >= TRIPLO) return { chave: 'TRIPLO' };
  if (vezes >= DOBRO) return { chave: 'DOBRO' };
  if (vezes >= QUASE_IGUAL) return { chave: 'UM_POUCO_MAIS' };
  if (vezes > 1 / QUASE_IGUAL) return { chave: 'IGUAL' };
  return { chave: 'MENOS' };
};

export const compararComControle = (receberam, controle) => {
  if (!controle || controle.pessoas < MINIMO_NO_CONTROLE)
    return { chave: 'POUCOS' };
  const esperadasNoControle = Math.max(
    controle.pessoas * taxa(receberam.compraram, receberam.pessoas),
    controle.compraram
  );
  if (esperadasNoControle < MINIMO_DE_COMPRAS_ESPERADAS)
    return { chave: 'POUCAS_COMPRAS' };
  if (controle.compraram === 0) return { chave: 'SO_QUEM_RECEBEU' };

  const lados = emGente(receberam, controle);
  return pelaDiferenca(lados.receberam / lados.controle);
};
