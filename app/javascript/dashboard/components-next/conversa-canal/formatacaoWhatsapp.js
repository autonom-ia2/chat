// Formatação do WhatsApp no balão (#1732): *negrito*, _itálico_, ~riscado~,
// ```mono```, `código`, listas (- , * , 1. ) e citação (> ). O painel lê markdown,
// onde *x* é itálico; o WhatsApp não. Este leitor anda o texto caractere a caractere
// (sem expressão regular) e devolve nós; o HTML sai escapado, e o balão ainda passa
// pelo mesmo sanitizador de sempre (v-dompurify-html).
//
// Regras do app, conferidas na ajuda do WhatsApp ("Como formatar suas mensagens"):
// - o marcador abre colado num caractere que não é espaço e fecha idem;
// - marcador grudado em letra ou número não abre nem fecha (2*3*4, nome_do_arquivo);
// - não atravessa quebra de linha, exceto o ``` ;
// - pode aninhar (*_x_*); dentro de ` e ``` nada é formatado.
import MarkdownIt from 'markdown-it';

const TRES_CRASES = '```';
const MARCAS = { '*': 'negrito', _: 'italico', '~': 'riscado', '`': 'codigo' };
const TAGS = { negrito: 'strong', italico: 'em', riscado: 's' };

// Só para achar e validar links, como o painel já faz (linkify do markdown-it).
const md = new MarkdownIt({ linkify: true });

const ehTexto = item => typeof item === 'string';
const ehEspaco = item => ehTexto(item) && item.trim() === '';
const ehDigito = c => ehTexto(c) && c.length === 1 && c >= '0' && c <= '9';
const ehLetraOuNumero = item =>
  ehTexto(item) &&
  (ehDigito(item) || item.toLowerCase() !== item.toUpperCase());

const textoDoItem = item => {
  if (ehTexto(item)) return item;
  if (item.tipo === 'mono') return `${TRES_CRASES}${item.texto}${TRES_CRASES}`;
  return item.texto;
};

// 1º passo: os blocos ``` (podem ter várias linhas). Viram um item só.
const separarMono = texto => {
  const partes = [];
  let resto = texto;
  let inicio = resto.indexOf(TRES_CRASES);
  while (inicio >= 0) {
    const fim = resto.indexOf(TRES_CRASES, inicio + TRES_CRASES.length);
    if (fim < 0) break;
    const dentro = resto.slice(inicio + TRES_CRASES.length, fim);
    if (dentro.trim()) {
      partes.push(resto.slice(0, inicio), { tipo: 'mono', texto: dentro });
      resto = resto.slice(fim + TRES_CRASES.length);
      inicio = resto.indexOf(TRES_CRASES);
    } else {
      inicio = resto.indexOf(TRES_CRASES, inicio + 1);
    }
  }
  partes.push(resto);
  return partes;
};

// Links viram um item só, para um _ ou * dentro do endereço não formatar nada.
const itensComLinks = trecho => {
  const achados = md.linkify.match(trecho) || [];
  const itens = [];
  let desde = 0;
  achados.forEach(achado => {
    if (!md.validateLink(achado.url)) return;
    itens.push(...Array.from(trecho.slice(desde, achado.index)));
    itens.push({ tipo: 'link', url: achado.url, texto: achado.text });
    desde = achado.lastIndex;
  });
  itens.push(...Array.from(trecho.slice(desde)));
  return itens;
};

// 2º passo: as linhas. Cada linha é uma lista de caracteres e itens (mono, link).
const separarLinhas = partes => {
  const linhas = [[]];
  partes.forEach(parte => {
    if (!ehTexto(parte)) {
      linhas[linhas.length - 1].push(parte);
      return;
    }
    parte.split('\n').forEach((trecho, posicao) => {
      if (posicao > 0) linhas.push([]);
      linhas[linhas.length - 1].push(...itensComLinks(trecho));
    });
  });
  return linhas;
};

// 3º passo: o começo da linha diz se ela é citação ou item de lista.
const tipoDaLinha = itens => {
  const [a, b, c, d] = itens;
  if (a === '>' && b === ' ') return { tipo: 'citacao', pular: 2 };
  if ((a === '-' || a === '*') && b === ' ') {
    return { tipo: 'marcador', pular: 2 };
  }
  if (ehDigito(a) && b === '.' && c === ' ') {
    return { tipo: 'numerada', numero: a, pular: 3 };
  }
  if (ehDigito(a) && ehDigito(b) && c === '.' && d === ' ') {
    return { tipo: 'numerada', numero: `${a}${b}`, pular: 4 };
  }
  return { tipo: 'paragrafo', pular: 0 };
};

// 4º passo: os marcadores dentro da linha.
const podeAbrir = (itens, i, ate) =>
  i + 1 < ate && !ehEspaco(itens[i + 1]) && !ehLetraOuNumero(itens[i - 1]);

const ondeFecha = (itens, i, ate) => {
  for (let j = i + 2; j < ate; j += 1) {
    if (
      itens[j] === itens[i] &&
      !ehEspaco(itens[j - 1]) &&
      !ehLetraOuNumero(itens[j + 1])
    ) {
      return j;
    }
  }
  return -1;
};

const lerTrecho = (itens, de, ate) => {
  const nos = [];
  let texto = '';
  const soltarTexto = () => {
    if (texto) nos.push({ tipo: 'texto', texto });
    texto = '';
  };
  let i = de;
  while (i < ate) {
    const item = itens[i];
    const tipo = ehTexto(item) ? MARCAS[item] : null;
    const fim =
      tipo && podeAbrir(itens, i, ate) ? ondeFecha(itens, i, ate) : -1;
    if (!ehTexto(item)) {
      soltarTexto();
      nos.push(item);
      i += 1;
    } else if (fim < 0) {
      texto += item;
      i += 1;
    } else {
      soltarTexto();
      nos.push(
        tipo === 'codigo'
          ? {
              tipo,
              texto: itens
                .slice(i + 1, fim)
                .map(textoDoItem)
                .join(''),
            }
          : { tipo, filhos: lerTrecho(itens, i + 1, fim) }
      );
      i = fim + 1;
    }
  }
  soltarTexto();
  return nos;
};

const MESMO_BLOCO = { marcador: 'lista', numerada: 'lista' };

// Lê o texto e devolve os blocos: paragrafo/citacao (linhas) e lista (itens).
export const lerFormatacao = texto => {
  const blocos = [];
  separarLinhas(separarMono(texto || '')).forEach(itens => {
    const linha = tipoDaLinha(itens);
    const nos = lerTrecho(itens, linha.pular, itens.length);
    const grupo = MESMO_BLOCO[linha.tipo] || linha.tipo;
    const ultimo = blocos[blocos.length - 1];
    const bloco = ultimo?.tipo === grupo ? ultimo : { tipo: grupo, linhas: [] };
    if (bloco !== ultimo) blocos.push(bloco);
    bloco.linhas.push(
      grupo === 'lista'
        ? { marca: linha.numero ? `${linha.numero}.` : '•', nos }
        : nos
    );
  });
  return blocos;
};

const escapar = texto =>
  texto
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const htmlDoNo = no => {
  if (no.tipo === 'texto') return escapar(no.texto);
  if (no.tipo === 'codigo') return `<code>${escapar(no.texto)}</code>`;
  if (no.tipo === 'mono') {
    return `<span class="font-mono whitespace-pre-wrap">${escapar(no.texto)}</span>`;
  }
  if (no.tipo === 'link') {
    const href = escapar(md.normalizeLink(no.url));
    return `<a href="${href}" class="link" rel="noreferrer noopener nofollow" target="_blank">${escapar(no.texto)}</a>`;
  }
  const tag = TAGS[no.tipo];
  return `<${tag}>${no.filhos.map(htmlDoNo).join('')}</${tag}>`;
};

const htmlDosNos = nos => nos.map(htmlDoNo).join('');

const htmlDoBloco = bloco => {
  if (bloco.tipo === 'lista') {
    const itens = bloco.linhas.map(
      ({ marca, nos }) =>
        `<div class="flex gap-2"><span class="shrink-0">${marca}</span><span>${htmlDosNos(nos)}</span></div>`
    );
    return `<div class="my-1">${itens.join('')}</div>`;
  }
  const linhas = bloco.linhas.map(htmlDosNos).join('<br>');
  if (bloco.tipo === 'citacao') {
    return `<blockquote class="not-italic my-1">${linhas}</blockquote>`;
  }
  return `<p>${linhas}</p>`;
};

// HTML do texto com a formatação do WhatsApp. Texto escapado; links validados.
export const formatarWhatsapp = texto =>
  lerFormatacao(texto).map(htmlDoBloco).join('');
