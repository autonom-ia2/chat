// #1601 — a linha de origem embaixo de cada campo em "Campos do card" (decisão
// do Rodrigo, 17/10): de onde veio o valor que está no campo, só texto. Vem da
// memória das IAs (fatos vigentes do card) e só aparece quando o fato é o MESMO
// valor do campo: valor diferente não ganha origem (seria de outro dado).
const TEXTOS = {
  cliente: 'CLIENTE',
  equipe: 'EQUIPE',
  ferramenta_resultado: 'FERRAMENTA',
  pessoa_corrigiu: 'CORRIGIDO',
};

const mesmoValor = (fato, valor) =>
  String(fato.valor ?? '').trim() === String(valor ?? '').trim();

// "17/10, 14:02" no fuso da conta (nunca o do navegador nem "Brasília").
export const quandoNoFuso = (iso, fuso, idioma) => {
  if (!iso) return '';
  return new Intl.DateTimeFormat(idioma, {
    timeZone: fuso,
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(iso));
};

// -> { texto, nome, quando, conversa, mensagem } ou null.
export const origemDoCampo = (fatos, chave, valor, { fuso, idioma }) => {
  if (valor === '' || valor == null) return null;
  const fato = (fatos || []).find(
    item =>
      item.escopo === 'card' &&
      item.tipo === 'fato' &&
      item.situacao === 'vigente' &&
      !item.expirado_em &&
      item.chave === chave &&
      TEXTOS[item.fonte] &&
      mesmoValor(item, valor)
  );
  if (!fato) return null;

  const corrigido = fato.fonte === 'pessoa_corrigiu';
  return {
    texto: TEXTOS[fato.fonte],
    nome: fato.corrigido_por_nome || '',
    quando: quandoNoFuso(
      corrigido ? fato.registrado_em : fato.valido_desde,
      fuso,
      idioma
    ),
    conversa: corrigido ? null : fato.prova_conversation_display_id || null,
    mensagem: corrigido ? null : fato.prova_message_id || null,
  };
};
