// #2897 — o arquivo da história do seguro (CSV que a planilha abre): data, hora,
// o que aconteceu e quem fez. Cada valor vai entre aspas; aspas de dentro dobram.
const SEPARADOR = ';';
// Marca que diz à planilha que o arquivo é UTF-8 (sem ela, o acento sai errado).
const MARCA_UTF8 = '﻿';

const entreAspas = valor =>
  `"${String(valor ?? '')
    .split('"')
    .join('""')}"`;

export const csvDaHistoria = linhas =>
  MARCA_UTF8 +
  linhas.map(linha => linha.map(entreAspas).join(SEPARADOR)).join('\r\n');

export const nomeDoArquivoDaHistoria = numero =>
  `historia-${numero || 'seguro'}.csv`;

export const baixarArquivo = (nome, conteudo) => {
  const endereco = URL.createObjectURL(
    new Blob([conteudo], { type: 'text/csv;charset=utf-8' })
  );
  const link = Object.assign(document.createElement('a'), {
    href: endereco,
    download: nome,
  });
  link.click();
  URL.revokeObjectURL(endereco);
};
