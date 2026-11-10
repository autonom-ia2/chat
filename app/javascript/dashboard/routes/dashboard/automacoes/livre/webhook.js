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

// Os lugares do catálogo já filtrado pelo gatilho (doAlvoDoGatilho). Na
// automação de conversa, o card dela é só para ler (#2716): a resposta não grava
// nele, e o servidor recusa (card_da_conversa_so_le).
export const basesDaResposta = catalogo => {
  const alvo = catalogo?.gatilhos?.find(
    item => item.tipo === catalogo.gatilho
  )?.alvo;
  return alvo === 'Conversation'
    ? BASES_DA_RESPOSTA.filter(base => base !== 'card.atributos')
    : BASES_DA_RESPOSTA;
};

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

// De onde vem o valor de uma linha: 'dado' (um dado do cliente, { $valor }),
// 'texto' (texto, número ou sim/não fixo) ou 'outro' (forma que o Guia monta e
// a tela ainda não edita: lista, objeto, outro valor calculado). Linha nova
// (null) ainda não tem origem.
export const origemDoValor = valor => {
  if (valor === null || valor === undefined) return null;
  if (['string', 'number', 'boolean'].includes(typeof valor)) return 'texto';
  const chaves = typeof valor === 'object' ? Object.keys(valor) : [];
  return chaves.length === 1 && chaves[0] === '$valor' ? 'dado' : 'outro';
};

// A forma 'outro' vai do jeito que o Guia montou: o servidor confere ao salvar.
const valorPronto = valor => {
  const origem = origemDoValor(valor);
  if (origem === 'dado') return Boolean(valor.$valor);
  if (origem === 'texto')
    return typeof valor !== 'string' || Boolean(valor.trim());
  return origem === 'outro';
};

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
