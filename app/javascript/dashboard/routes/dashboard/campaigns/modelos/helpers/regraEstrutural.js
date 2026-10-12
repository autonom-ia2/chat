// A forma dos botões que a Meta exige (#1380), conferida antes de enviar. É o
// mesmo que o servidor confere em Whatsapp::Templates::SubmitFormat: o que
// passa aqui passa lá. Só forma (campo vazio, tamanho, tipo de mensagem); o
// sentido do texto quem julga é o WhatsApp. Sem expressão regular (regra do
// Rodrigo).

// "Copiar código" só existe em mensagens de divulgação (MARKETING).
export const BOTOES_SO_DE_DIVULGACAO = ['copiar_codigo'];
export const CODIGO_MAXIMO = 15;
export const LIMITE_DO_BOTAO = 25;

const LETRAS_E_NUMEROS =
  'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

const temLetras = texto => (texto || '').trim().length > 0;

// Código de exemplo do botão "Copiar código" (e cupom da oferta): de 1 a 15
// letras e números, sem espaço.
export const codigoDeExemploValido = codigo => {
  const valor = codigo || '';
  return (
    valor.length >= 1 &&
    valor.length <= CODIGO_MAXIMO &&
    valor.split('').every(letra => LETRAS_E_NUMEROS.includes(letra))
  );
};

// Endereço de site completo: começa com http:// ou https://, só letras do
// teclado sem espaço (a mesma régua do servidor, que lê com URI) e um domínio
// com ponto. O final variável ({{1}}) de modelo feito fora fica de fora da
// leitura. Sem expressão regular.
const INICIOS = ['https://', 'http://'];
const semEspacoEAscii = texto =>
  texto
    .split('')
    .every(letra => letra.charCodeAt(0) > 32 && letra.charCodeAt(0) < 127);
export const enderecoValido = endereco => {
  const base = (endereco || '').trim().split('{{')[0];
  if (!INICIOS.some(inicio => base.startsWith(inicio))) return false;
  if (!semEspacoEAscii(base)) return false;
  try {
    return new URL(base).hostname.includes('.');
  } catch {
    return false;
  }
};

// Telefone com o código do país: começa com +, só números, espaço, traço e
// parênteses, com 8 a 15 números. Vai para a Meta só com + e os números.
const NUMEROS = '0123456789';
const numerosDe = telefone =>
  (telefone || '')
    .split('')
    .filter(letra => NUMEROS.includes(letra))
    .join('');
export const telefoneValido = telefone => {
  const valor = (telefone || '').trim();
  const quantos = numerosDe(valor).length;
  return (
    valor.startsWith('+') &&
    valor.split('').every(letra => `${NUMEROS}+ -()`.includes(letra)) &&
    quantos >= 8 &&
    quantos <= 15
  );
};
export const telefoneNaMeta = telefone => `+${numerosDe(telefone)}`;

// Todos os problemas de um botão (lista vazia: está certo). `tipo` é o tipo
// da mensagem (aviso, divulgacao, codigo). Botão só de divulgação num aviso não
// é conferido além disso: ele tem de sair.
export const problemasDoBotao = (botao, tipo) => {
  if (BOTOES_SO_DE_DIVULGACAO.includes(botao.tipo) && tipo !== 'divulgacao') {
    return ['SO_DIVULGACAO'];
  }
  // O texto do "Copiar código" é fixo do WhatsApp: a tela nem pede.
  const temTexto = botao.tipo !== 'copiar_codigo';
  return [
    temTexto && !temLetras(botao.texto) && 'SEM_TEXTO',
    temTexto &&
      (botao.texto || '').trim().length > LIMITE_DO_BOTAO &&
      'TEXTO_LONGO',
    botao.tipo === 'site' &&
      !enderecoValido(botao.valor) &&
      'SITE_SEM_ENDERECO',
    // Site com final variável ({{1}}), vindo de fora da tela: vai com o exemplo.
    botao.tipo === 'site' &&
      (botao.valor || '').includes('{{') &&
      !temLetras(botao.exemplo) &&
      'SITE_SEM_EXEMPLO',
    botao.tipo === 'ligar' &&
      !telefoneValido(botao.valor) &&
      'LIGAR_SEM_NUMERO',
    botao.tipo === 'copiar_codigo' &&
      !codigoDeExemploValido(botao.valor) &&
      'CODIGO_SEM_EXEMPLO',
  ].filter(Boolean);
};

// Itens da conferência ("O que o WhatsApp confere") para os botões da mensagem
// comum. Cada regra só aparece quando há um botão a que ela se aplica.
const ITENS_DOS_BOTOES = [
  { chave: 'BOTOES', problema: 'SEM_TEXTO', aplica: () => true },
  {
    chave: 'BOTOES_TAMANHO',
    problema: 'TEXTO_LONGO',
    aplica: botao => botao.tipo !== 'copiar_codigo',
  },
  {
    chave: 'BOTAO_SITE_EXEMPLO',
    problema: 'SITE_SEM_EXEMPLO',
    aplica: botao =>
      botao.tipo === 'site' && (botao.valor || '').includes('{{'),
  },
  {
    chave: 'BOTAO_SITE',
    problema: 'SITE_SEM_ENDERECO',
    aplica: botao => botao.tipo === 'site',
  },
  {
    chave: 'BOTAO_LIGAR',
    problema: 'LIGAR_SEM_NUMERO',
    aplica: botao => botao.tipo === 'ligar',
  },
  {
    chave: 'BOTAO_CODIGO',
    problema: 'CODIGO_SEM_EXEMPLO',
    aplica: (botao, tipo) =>
      botao.tipo === 'copiar_codigo' && tipo === 'divulgacao',
  },
  {
    chave: 'SO_DIVULGACAO',
    problema: 'SO_DIVULGACAO',
    aplica: (botao, tipo) =>
      BOTOES_SO_DE_DIVULGACAO.includes(botao.tipo) && tipo !== 'divulgacao',
  },
];

export const conferirBotoes = (botoes, tipo) =>
  ITENS_DOS_BOTOES.filter(
    item => item.chave === 'BOTOES' || botoes.some(b => item.aplica(b, tipo))
  ).map(item => ({
    chave: item.chave,
    ok: !botoes.some(botao =>
      problemasDoBotao(botao, tipo).includes(item.problema)
    ),
  }));

// A Meta quer as respostas rápidas juntas: aqui, sempre antes dos outros botões,
// cada grupo na ordem em que foi posto. A tela guarda e mostra nesta ordem.
export const ordenarBotoes = botoes => [
  ...botoes.filter(botao => botao.tipo === 'resposta'),
  ...botoes.filter(botao => botao.tipo !== 'resposta'),
];
