// chat#1655: erro de envio da Meta (WhatsApp Cloud) em linguagem simples no balão.
// O texto vem de `content_attributes.external_error`, nos formatos "131042: título"
// ou "(#132001) mensagem". A frase é escolhida pelo número do código, nunca pelo texto.

const NAMESPACE = 'ERRO_DA_META';
const DESCONHECIDO = 'DESCONHECIDO';

const CHAVE_POR_CODIGO = {
  131042: 'SEM_PAGAMENTO',
  131047: 'PASSOU_24_HORAS',
  131026: 'NUMERO_NAO_RECEBE',
  131049: 'LIMITE_PROPAGANDA',
  131050: 'CLIENTE_RECUSOU_PROPAGANDA',
  131051: 'TIPO_NAO_SUPORTADO',
  131053: 'ARQUIVO_RECUSADO',
  130472: 'TESTE_DA_META',
  368: 'CONTA_BLOQUEADA',
  131031: 'CONTA_BLOQUEADA',
  131048: 'LIMITE_SPAM',
  131056: 'MUITAS_PARA_O_MESMO',
  190: 'LIGACAO_VENCEU',
  132000: 'MODELO_CAMPOS_VAZIOS',
  132001: 'MODELO_NAO_EXISTE',
  132005: 'MODELO_TEXTO_GRANDE',
  132007: 'MODELO_RECUSADO',
  132012: 'MODELO_FORMATO_ERRADO',
  132015: 'MODELO_PAUSADO',
  132016: 'MODELO_DESLIGADO',
};

// Erros em que reenviar a mesma mensagem não adianta.
const SEM_REENVIO = ['131047', '131050', '132016'];

export const CODIGOS_CONHECIDOS = Object.keys(CHAVE_POR_CODIGO);
export const CHAVES = [
  ...new Set([...Object.values(CHAVE_POR_CODIGO), DESCONHECIDO]),
];

// Códigos da Meta têm de 3 a 6 dígitos; menos que isso ("10:30 …", "3: …") não é código.
const MIN_DIGITOS = 3;

const soDigitos = texto =>
  texto.length >= MIN_DIGITOS && [...texto].every(c => c >= '0' && c <= '9');

const trechoDoCodigo = texto => {
  if (texto.startsWith('(#')) {
    const fim = texto.indexOf(')');
    return fim > 2 ? texto.slice(2, fim) : '';
  }
  return texto.split(':')[0].trim();
};

export const codigoDoErro = texto => {
  const trecho = trechoDoCodigo((texto || '').trim());
  return soDigitos(trecho) ? trecho : null;
};

/**
 * @param {string} texto - `external_error` da mensagem
 * @param {boolean} ehWhatsapp - a caixa é `Channel::Whatsapp`
 * @returns {{ chave: string|null, detalhe: string, podeReenviar: boolean }}
 *   `chave` é o prefixo i18n (com `.O_QUE` e `.FAZER`); null deixa a tela como antes.
 */
export const erroDaMeta = (texto, ehWhatsapp) => {
  const detalhe = texto || '';
  const codigo = ehWhatsapp ? codigoDoErro(detalhe) : null;
  if (!codigo) return { chave: null, detalhe, podeReenviar: true };

  const nome = CHAVE_POR_CODIGO[codigo] || DESCONHECIDO;
  return {
    chave: `${NAMESPACE}.${nome}`,
    detalhe,
    podeReenviar: !SEM_REENVIO.includes(codigo),
  };
};
