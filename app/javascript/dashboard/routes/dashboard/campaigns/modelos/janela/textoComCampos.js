// O texto da conversa aberta guarda os campos na sintaxe do catálogo
// ({{cliente.primeiro_nome}}). Aqui ele vira pedaços ({ t: 'texto' | 'campo',
// v }, o formato do ModeloEditorTexto) para a tela mostrar o campo como
// etiqueta, e vira a prévia com um exemplo no lugar do campo. Leitura por posição de "{{" e "}}", sem expressão regular.
const ABRE = '{{';
const FECHA = '}}';

export const pedacos = texto => {
  const lista = [];
  let resto = texto || '';
  while (resto) {
    const inicio = resto.indexOf(ABRE);
    const fim = inicio < 0 ? -1 : resto.indexOf(FECHA, inicio);
    if (inicio < 0 || fim < 0) {
      lista.push({ t: 'texto', v: resto });
      break;
    }
    if (inicio > 0) lista.push({ t: 'texto', v: resto.slice(0, inicio) });
    lista.push({
      t: 'campo',
      v: resto.slice(inicio + ABRE.length, fim).trim(),
    });
    resto = resto.slice(fim + FECHA.length);
  }
  return lista;
};

export const previa = (texto, exemplos) =>
  pedacos(texto)
    .map(pedaco => (pedaco.t === 'campo' ? exemplos[pedaco.v] || '' : pedaco.v))
    .join('');

// Pedaços do editor (mesmo formato do ModeloEditorTexto) → texto guardado.
export const juntar = lista =>
  lista
    .map(pedaco =>
      pedaco.t === 'campo' ? `${ABRE}${pedaco.v}${FECHA}` : pedaco.v
    )
    .join('');

// Link só entra por campo (decisão do Rodrigo, 13/10/2026), conferido só no
// texto fixo, com métodos de string (sem expressão regular). A mesma regra do
// backend (CampaignJourney::ConversaAberta::Texto):
// - "://" ou "www." trava (`linkInequivoco`);
// - um ponto entre duas letras numa palavra ("loja.com") só avisa
//   (`pareceLink`), porque erra em "Sr.Paulo" e "Ltda.São Paulo".
const MARCAS_DE_ENDERECO = ['://', 'www.'];
const letra = char =>
  Boolean(char) && char.toUpperCase() !== char.toLowerCase();
const pareceDominio = palavra =>
  [...palavra].some(
    (char, i, letras) =>
      char === '.' && i > 0 && letra(letras[i - 1]) && letra(letras[i + 1])
  );

const textoFixo = texto =>
  pedacos(texto)
    .filter(pedaco => pedaco.t === 'texto')
    .map(pedaco => pedaco.v)
    .join(' ')
    .toLowerCase();

export const linkInequivoco = texto => {
  const fixo = textoFixo(texto);
  return MARCAS_DE_ENDERECO.some(marca => fixo.includes(marca));
};

export const pareceLink = texto =>
  !linkInequivoco(texto) &&
  textoFixo(texto).split(' ').filter(Boolean).some(pareceDominio);
