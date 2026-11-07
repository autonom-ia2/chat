// G13 (#2670) — o passo "mandar dados para outro sistema" na tela: a frase da
// linha, o pronto de cada peça do painel e a conversão do corpo (objeto na
// receita, linhas na tela).
const W = 'AUTOMACAO_LIVRE.WEBHOOK';

// Onde a resposta pode gravar: os campos personalizados do card, do contato e
// da conversa (o servidor confere de novo, Autonomia::Automacao::PassoDeWebhook).
export const BASES_DA_RESPOSTA = [
  'card.atributos',
  'contato.atributos',
  'conversa.atributos',
];

// O host do endereço, ou '' quando ainda não é um endereço.
export const hostDoEndereco = url => {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
};

// Só https e com host. O resto (rede interna, a própria plataforma) quem
// recusa é o servidor, ao salvar.
export const enderecoPronto = url =>
  typeof url === 'string' &&
  url.trim().startsWith('https://') &&
  Boolean(hostDoEndereco(url.trim()));

export const descricaoPronta = descricao =>
  typeof descricao === 'string' && Boolean(descricao.trim());

// O corpo da receita ({ nome: { $valor } }) em linhas, na ordem das chaves.
export const linhasDoCorpo = corpo =>
  Object.entries(corpo || {}).map(([nome, valor]) => ({ nome, valor }));

const valorPronto = valor => Boolean(valor?.$valor);

// As linhas de volta em corpo. Linha sem nome, com nome repetido ou sem dado
// escolhido deixa a marca '' no corpo: o "Salvar" fica preso até a pessoa
// corrigir, e nenhuma linha some sem aviso.
export const corpoDasLinhas = linhas => {
  const nomes = linhas.map(linha => linha.nome.trim());
  const incompleta = linhas.some(
    (linha, i) =>
      !nomes[i] || nomes.indexOf(nomes[i]) !== i || !valorPronto(linha.valor)
  );
  const corpo = Object.fromEntries(
    linhas.flatMap((linha, i) => (nomes[i] ? [[nomes[i], linha.valor]] : []))
  );
  return incompleta ? { ...corpo, '': null } : corpo;
};

export const corpoPronto = corpo =>
  !Object.prototype.hasOwnProperty.call(corpo || {}, '') &&
  Object.values(corpo || {}).every(valorPronto);

export const gravarPronto = gravar =>
  (gravar || []).every(item => item.chave?.trim() && item.destino);

// "Mandar para cobranca.exemplo.com: Mandar ao sistema de cobrança".
export const fraseDoWebhook = (passo, t) => {
  const host = hostDoEndereco(passo.url || '') || t(`${W}.OUTRO_SISTEMA`);
  const descricao = (passo.descricao || '').trim();
  return descricao
    ? t(`${W}.FRASE`, { host, descricao })
    : t(`${W}.FRASE_SEM_DESCRICAO`, { host });
};
