// Um nome por conta, sem diferenciar maiúsculas nem espaços nas pontas (#2185, CustomRole#name_not_taken).
const normal = nome => (nome || '').trim().toLowerCase();

export const nomeEmUso = (nome, funcoes, idAtual = null) =>
  funcoes.some(
    funcao => funcao.id !== idAtual && normal(funcao.name) === normal(nome)
  );

// "Atendente 2" → "Atendente": o número do fim é a contagem de cópias, não parte do nome.
const semNumeroNoFim = nome => {
  const partes = nome.trim().split(' ');
  const ultima = partes[partes.length - 1];
  const ehNumero = ultima !== '' && Number.isInteger(Number(ultima));
  return partes.length > 1 && ehNumero
    ? partes.slice(0, -1).join(' ').trim()
    : nome.trim();
};

// O primeiro nome livre a partir deste: ele mesmo, ou com " 2", " 3"… `recusados` são nomes que o servidor recusou e
// a lista não mostra (o de uma integração, decisão 6).
export const primeiroNomeLivre = (nome, funcoes, recusados = []) => {
  const base = semNumeroNoFim(nome);
  const usado = candidato =>
    nomeEmUso(candidato, funcoes) ||
    recusados.some(recusado => normal(recusado) === normal(candidato));
  if (!usado(base)) return base;
  let numero = 2;
  while (usado(`${base} ${numero}`)) numero += 1;
  return `${base} ${numero}`;
};
