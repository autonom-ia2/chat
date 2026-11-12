// #2896 — a demonstração confere o valor que conserta uma linha como o servidor
// (app/services/contact_imports/trazer/conserto.rb), com os mesmos motivos em
// código: o valor vazio, o telefone que não é celular do Brasil, o e-mail que
// não é e-mail e o texto que começa com sinal de fórmula. Devolve `{ motivo }`
// quando o valor não vale ou `{ corrigido }`, o valor como vai ser gravado.
// Nada aqui interpreta o que a pessoa quis dizer: só confere o formato, com
// métodos de texto.
import { soDigitos } from '../fonte/texto';

const PAIS = '55';
const TAMANHO_DO_CELULAR = 11;
const FIM_DO_DDD = 2;
const PRIMEIRO_DO_CELULAR = '9';
const ZERO = '0';
const ARROBA = '@';
const MAIS = '+';
const SINAIS_DE_FORMULA = ['=', '-', ARROBA];
const ESPACO = ' ';

const recusado = motivo => ({ motivo });
const aceito = corrigido => ({ corrigido });

const ehDigito = letra => letra >= '0' && letra <= '9';
const ehEspaco = letra => letra.trim() === '';

// O texto que uma planilha leria como fórmula: começa com =, - ou @, ou com um
// "+" que não é o de um número ("+55…" vale, no telefone e fora dele).
const comecaComSinal = texto =>
  SINAIS_DE_FORMULA.includes(texto.charAt(0)) ||
  (texto.startsWith(MAIS) && !ehDigito(texto.charAt(1)));

// Celular do Brasil: DDD (dois dígitos, nenhum zero) e nove dígitos começando
// com 9, com ou sem o 55 na frente. Sai como vai ser gravado: +5511987650004.
const celularDoBrasil = texto => {
  const digitos = soDigitos(texto);
  const comPais =
    digitos.length === PAIS.length + TAMANHO_DO_CELULAR &&
    digitos.startsWith(PAIS);
  const local = comPais ? digitos.slice(PAIS.length) : digitos;
  const valido =
    local.length === TAMANHO_DO_CELULAR &&
    !local.slice(0, FIM_DO_DDD).includes(ZERO) &&
    local.charAt(FIM_DO_DDD) === PRIMEIRO_DO_CELULAR;
  return valido ? `+${PAIS}${local}` : null;
};

const telefone = valor => {
  if (!valor) return recusado('blank_phone_number');
  if (comecaComSinal(valor)) return recusado('formula_phone_number');
  const corrigido = celularDoBrasil(valor);
  return corrigido
    ? aceito(corrigido)
    : recusado('invalid_brazilian_mobile_number');
};

// Um "@" só, com alguma coisa antes e depois, e nenhum espaço.
const pareceEmail = texto => {
  const partes = texto.split(ARROBA);
  return (
    partes.length === 2 &&
    partes.every(parte => parte && ![...parte].some(ehEspaco))
  );
};

const email = valor => {
  const minusculo = valor.toLowerCase();
  if (!minusculo) return recusado('blank_email');
  if (!pareceEmail(minusculo)) return recusado('invalid_email');
  return comecaComSinal(minusculo)
    ? recusado('formula_detected')
    : aceito(minusculo);
};

// O nome fica com um espaço só entre as palavras.
const umEspacoSo = texto =>
  [...texto]
    .map(letra => (ehEspaco(letra) ? ESPACO : letra))
    .join('')
    .split(ESPACO)
    .filter(Boolean)
    .join(ESPACO);

const nome = valor => {
  if (!valor) return recusado('blank_name');
  return comecaComSinal(valor)
    ? recusado('formula_detected')
    : aceito(umEspacoSo(valor));
};

// A linha sem telefone nem e-mail aceita os dois: com "@" é e-mail.
const contato = valor => {
  if (!valor) return recusado('missing_contact');
  return valor.includes(ARROBA) ? email(valor) : telefone(valor);
};

const CONFERE = new Map([
  ['telefone', telefone],
  ['email', email],
  ['nome', nome],
  ['sem_contato', contato],
]);

// `tipo` é o da linha (o campo que ela conserta); `valor`, o que a pessoa
// escreveu.
export const conferirValor = (tipo, valor) =>
  CONFERE.get(tipo)(String(valor ?? '').trim());
