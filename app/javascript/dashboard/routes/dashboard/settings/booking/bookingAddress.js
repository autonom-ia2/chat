// Endereço da página de agendamento (#1282, #1299): o `<página>` de
// `/a/<conta>/<página>`. As mesmas regras de formato do servidor
// (Crm::BookingV2::ShortName), conferidas caractere a caractere contra um
// conjunto fechado. O que depende do banco (nome do sistema, nome que outra
// página da conta já usa) quem responde é o servidor.
export const ADDRESS_MIN = 3;
export const ADDRESS_MAX = 40;
const ALLOWED = 'abcdefghijklmnopqrstuvwxyz0123456789-';
const AS_HYPHEN = [' ', '_'];

// O que a pessoa digita vira endereço válido na hora: minúsculas, sem acento
// (a letra fica, o acento sai) e espaço como hífen.
export const cleanAddress = value =>
  [
    ...String(value || '')
      .toLowerCase()
      .normalize('NFD'),
  ]
    .map(char => (AS_HYPHEN.includes(char) ? '-' : char))
    .filter(char => ALLOWED.includes(char))
    .join('')
    .slice(0, ADDRESS_MAX);

// Devolve o código do problema (os mesmos do servidor) ou null. Vazio não é
// problema: a página sem endereço usa o link comprido.
export const addressProblem = value => {
  const name = String(value || '');
  if (!name) return null;
  if (name.length < ADDRESS_MIN) return 'too_short';
  if (name.length > ADDRESS_MAX) return 'too_long';
  if (![...name].every(char => ALLOWED.includes(char))) return 'invalid_chars';
  if (name.startsWith('-') || name.endsWith('-')) return 'hyphen_edge';
  return null;
};

// O link como a pessoa vai ler: `<site>/a/<conta>/<página>`.
export const addressUrl = (name, account, host = window.location.host) =>
  `${host}/a/${account}/${name}`;
