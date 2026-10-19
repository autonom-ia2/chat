// Nome que o atendente lê numa etiqueta (#1823). Só exibição: o título técnico
// (`label.title`) continua o mesmo no banco, nos filtros, na URL, nas automações
// e na API. Sem regex (regra do Rodrigo): só métodos de string.
const SEPARADOR_TECNICO = '_';

export const TAMANHO_MAXIMO_DO_NOME = 80;

export const nomeLegivelDoTitulo = (titulo = '') => {
  const palavras = titulo.split(SEPARADOR_TECNICO).filter(Boolean).join(' ');
  if (!palavras) return '';
  return palavras.charAt(0).toUpperCase() + palavras.slice(1);
};

// Ordem (decisão do Rodrigo, 18/10): nome guardado aqui → nome no celular (F1b,
// etiqueta vinculada ao WhatsApp) → derivado do título (etiqueta sem nome guardado).
export const nomeDaEtiqueta = (
  titulo,
  { nomeGuardado, nomeNoCelular } = {}
) => {
  if (!titulo) return '';
  return nomeGuardado || nomeNoCelular || nomeLegivelDoTitulo(titulo);
};

// O `title` que o formulário envia: minúsculo, espaço vira "_" e sai o que a
// validação do Label recusa (emoji, pontuação). Fica letra (de qualquer
// alfabeto, com acento), dígito, "_" e "-".
const DIGITOS = '0123456789';
const caractereAceito = ch =>
  ch.toLowerCase() !== ch.toUpperCase() ||
  DIGITOS.includes(ch) ||
  ch === SEPARADOR_TECNICO ||
  ch === '-';
const soAceitos = palavra => [...palavra].filter(caractereAceito).join('');

// A validação do Label exige letra ou dígito no começo ("-vip" é recusado).
const SEPARADORES = [SEPARADOR_TECNICO, '-'];
const semSeparadorNoInicio = texto => {
  let inicio = 0;
  while (inicio < texto.length && SEPARADORES.includes(texto[inicio])) {
    inicio += 1;
  }
  return texto.slice(inicio);
};

// NFC junta o acento digitado em separado ("e" + "´") à letra, e ele não se perde.
// Letra sem maiúscula/minúscula (chinês, árabe, hebraico) fica de fora: separá-la
// de símbolo e emoji pediria regex (regra do Rodrigo); o formulário avisa.
export const tituloTecnicoDoNome = (nome = '') =>
  semSeparadorNoInicio(
    nome
      .normalize('NFC')
      .toLowerCase()
      .split(' ')
      .map(soAceitos)
      .filter(Boolean)
      .join(SEPARADOR_TECNICO)
  );

// Mesmo texto para o atendente: ignora maiúsculas e espaços nas pontas.
export const mesmoNome = (a = '', b = '') =>
  a.trim().toLowerCase() === b.trim().toLowerCase();
