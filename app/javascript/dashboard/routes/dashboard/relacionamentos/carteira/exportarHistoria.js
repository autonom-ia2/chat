// #2898 — o arquivo do histórico do seguro (CSV que a planilha abre): data,
// hora, o que aconteceu e quem fez. Cada valor vai entre aspas; aspas de dentro
// dobram. O nome do arquivo é neutro, como o do PDF da apólice: não leva o
// número da apólice nem o nome de ninguém.
const SEPARADOR = ';';
// Marca que diz à planilha que o arquivo é UTF-8 (sem ela, o acento sai errado).
const MARCA_UTF8 = '\uFEFF';
const NOME_DO_ARQUIVO = 'historico-do-seguro.csv';
const SOLTAR_O_ENDERECO_EM_MS = 1000;
// Um valor que começa por um destes a planilha lê como fórmula (a tabulação e
// o retorno de carro também abrem uma). O apóstrofo na frente faz ela ler como
// texto.
const COMECO_DE_FORMULA = ['=', '+', '-', '@', '\t', '\r'];

const comoTexto = valor => {
  const texto = String(valor ?? '');
  return COMECO_DE_FORMULA.some(sinal => texto.startsWith(sinal))
    ? `'${texto}`
    : texto;
};

const entreAspas = valor => `"${comoTexto(valor).split('"').join('""')}"`;

export const csvDoHistorico = linhas =>
  MARCA_UTF8 +
  linhas.map(linha => linha.map(entreAspas).join(SEPARADOR)).join('\r\n');

export const nomeDoArquivoDoHistorico = () => NOME_DO_ARQUIVO;

export const baixarArquivo = (nome, conteudo) => {
  const endereco = URL.createObjectURL(
    new Blob([conteudo], { type: 'text/csv;charset=utf-8' })
  );
  const link = Object.assign(document.createElement('a'), {
    href: endereco,
    download: nome,
  });
  // Fora da página alguns navegadores ignoram o clique; e o endereço só é
  // solto depois, para o navegador ter tempo de começar a baixar.
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(endereco), SOLTAR_O_ENDERECO_EM_MS);
};
