// A forma dos botões que a Meta exige (#1380), conferida antes de enviar. É o
// mesmo que o servidor confere em Whatsapp::Templates::SubmitFormat: o que
// passa aqui passa lá. Só forma (campo vazio, tamanho, tipo de mensagem); o
// sentido do texto quem julga é o WhatsApp. Sem expressão regular (regra do
// Rodrigo).

// "Copiar código" só existe em mensagens de divulgação (MARKETING).
export const BOTOES_SO_DE_DIVULGACAO = ['copiar_codigo'];
export const CODIGO_MAXIMO = 15;

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

// Todos os problemas de um botão (lista vazia: está certo). `tipo` é o tipo
// da mensagem (aviso, divulgacao, codigo). Botão só de divulgação num aviso não
// é conferido além disso: ele tem de sair.
export const problemasDoBotao = (botao, tipo) => {
  if (BOTOES_SO_DE_DIVULGACAO.includes(botao.tipo) && tipo !== 'divulgacao') {
    return ['SO_DIVULGACAO'];
  }
  return [
    !temLetras(botao.texto) && 'SEM_TEXTO',
    botao.tipo === 'site' && !temLetras(botao.valor) && 'SITE_SEM_ENDERECO',
    botao.tipo === 'ligar' && !temLetras(botao.valor) && 'LIGAR_SEM_NUMERO',
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
