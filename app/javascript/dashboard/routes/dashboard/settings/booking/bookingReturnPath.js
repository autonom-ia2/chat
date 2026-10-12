// `?voltar=` do Agendamento (#1371): para onde o "Voltar" do assistente leva
// quem chegou de outra tela (ex.: a gaveta "Marcar reuniões" do agente). Só
// vale caminho do próprio painel, na conta aberta, e fora do próprio
// Agendamento (voltar para cá reabriria o assistente em laço). O navegador
// normaliza o endereço (`..`, `%2e%2e`, `\`) e a conferência é feita depois,
// com métodos de string, sem expressão regular. Caractere de controle (tab,
// quebra de linha), que o navegador apagaria em silêncio, já recusa. Qualquer
// outra coisa é ignorada (null).
const hasControlChar = value =>
  [...value].some(char => char.charCodeAt(0) < 32 || char === '\u007f');

const parse = value => {
  try {
    return new URL(value, window.location.origin);
  } catch {
    return null;
  }
};

export const internalReturnPath = (value, accountId) => {
  if (typeof value !== 'string' || !accountId) return null;
  if (!value.startsWith('/') || hasControlChar(value)) return null;

  const url = parse(value);
  if (!url || url.origin !== window.location.origin) return null;

  const { pathname } = url;
  const accountRoot = `/app/accounts/${accountId}/`;
  if (!pathname.startsWith(accountRoot)) return null;
  if (pathname.includes('//') || pathname.split('/').includes('..'))
    return null;

  const inside = pathname.slice(accountRoot.length);
  if (inside.startsWith('crm/booking') || inside.startsWith('settings/booking'))
    return null;

  return `${pathname}${url.search}${url.hash}`;
};
