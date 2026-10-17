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

// Um marcador no fim do endereço que foi aberto antes do link (*site.com*) fecha a
// formatação; não é do link. Sem abertura antes (site.com/_a_), fica no endereço.
const fimSemMarcador = (trecho, achado) => {
  const antes = trecho.slice(0, achado.index);
  let fim = achado.lastIndex;
  const ehMarcadorAberto = c => MARCAS[c] && c !== '`' && antes.includes(c);
  while (fim > achado.index && ehMarcadorAberto(trecho[fim - 1])) fim -= 1;
  return fim;
};

// Pedaços de texto e links. O texto entre eles fica como veio.
const pedacosComLinks = trecho => {
  const pedacos = [];
  let desde = 0;
  (md.linkify.match(trecho) || []).forEach(achado => {
    const fim = fimSemMarcador(trecho, achado);
    const url = achado.url.slice(
      0,
      achado.url.length - (achado.lastIndex - fim)
    );
    if (fim <= achado.index || !md.validateLink(url)) return;
    pedacos.push(trecho.slice(desde, achado.index));
    pedacos.push({ tipo: 'link', url, texto: trecho.slice(achado.index, fim) });
    desde = fim;
  });
  pedacos.push(trecho.slice(desde));
  return pedacos;
};

// Links viram um item só, para um _ ou * dentro do endereço não formatar nada.
const itensComLinks = trecho =>
  pedacosComLinks(trecho).flatMap(pedaco =>
    ehTexto(pedaco) ? Array.from(pedaco) : [pedaco]
  );

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

// 4º passo: os marcadores dentro da linha. `largura` é 1 (*x*); no modo tolerante, para
// texto de robô e IA, também 2 (**x**, ~~x~~) e 3 (***x***), como o envio lê
// (WhatsAppRenderer, automatico: true).
const repete = (itens, i, marca, largura) =>
  Array.from({ length: largura }).every((_, k) => itens[i + k] === marca);

const podeAbrir = (itens, i, ate, largura) =>
  i + largura < ate &&
  !ehEspaco(itens[i + largura]) &&
  !ehLetraOuNumero(itens[i - 1]);

const ondeFecha = (itens, i, ate, largura, tolerante) => {
  for (let j = i + largura + 1; j + largura <= ate; j += 1) {
    // Tolerante: numa sequência maior (***), fecha no fim dela (**a *b***).
    let fim = j;
    while (
      tolerante &&
      fim + largura < ate &&
      itens[fim + largura] === itens[i]
    ) {
      fim += 1;
    }
    if (
      repete(itens, j, itens[i], largura) &&
      !ehEspaco(itens[j - 1]) &&
      !ehLetraOuNumero(itens[fim + largura])
    ) {
      return fim;
    }
  }
  return -1;
};

const LARGURAS_TOLERANTES = { '*': 3, '~': 2 };

const tamanhoDaSequencia = (itens, i) => {
  let tamanho = 1;
  while (itens[i + tamanho] === itens[i]) tamanho += 1;
  return tamanho;
};

// As larguras a tentar, da maior para a menor.
const largurasEm = (itens, i, tolerante) => {
  const maxima = tolerante ? LARGURAS_TOLERANTES[itens[i]] || 1 : 1;
  const maior = Math.min(maxima, tamanhoDaSequencia(itens, i));
  return Array.from({ length: maior }, (_, k) => maior - k);
};

// Onde a marca em `i` abre e fecha: { largura, fim }, ou null quando é texto.
const marcaEm = (itens, i, ate, tolerante) =>
  largurasEm(itens, i, tolerante).reduce((achada, largura) => {
    if (achada || !podeAbrir(itens, i, ate, largura)) return achada;
    const fim = ondeFecha(itens, i, ate, largura, tolerante);
    return fim < 0 ? null : { largura, fim };
  }, null);

// Negrito dentro de negrito vira um negrito só, como no envio do robô.
const semNegrito = nos =>
  nos.flatMap(no => {
    if (no.tipo === 'negrito') return semNegrito(no.filhos);
    return no.filhos ? [{ ...no, filhos: semNegrito(no.filhos) }] : [no];
  });

const filhosDe = (tipo, filhos, tolerante) =>
  tolerante && tipo === 'negrito' ? semNegrito(filhos) : filhos;

const lerTrecho = (itens, de, ate, tolerante) => {
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
    const marca = tipo ? marcaEm(itens, i, ate, tolerante) : null;
    if (!ehTexto(item)) {
      soltarTexto();
      nos.push(item);
      i += 1;
    } else if (!marca) {
      texto += item;
      i += 1;
    } else {
      const { largura, fim } = marca;
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
          : {
              tipo,
              filhos: filhosDe(
                tipo,
                lerTrecho(itens, i + largura, fim, tolerante),
                tolerante
              ),
            }
      );
      i = fim + largura;
    }
  }
  soltarTexto();
  return nos;
};

const MESMO_BLOCO = { marcador: 'lista', numerada: 'lista' };

// Lê o texto e devolve os blocos: paragrafo/citacao (linhas) e lista (itens).
// `tolerante`: texto de robô/IA, que mistura o markdown (**x**, ~~x~~) com o WhatsApp.
export const lerFormatacao = (texto, { tolerante = false } = {}) => {
  const blocos = [];
  separarLinhas(separarMono(texto || '')).forEach(itens => {
    const linha = tipoDaLinha(itens);
    const nos = lerTrecho(itens, linha.pular, itens.length, tolerante);
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

const htmlDoLink = no => {
  const href = escapar(md.normalizeLink(no.url));
  return `<a href="${href}" class="link" rel="noreferrer noopener nofollow" target="_blank">${escapar(no.texto)}</a>`;
};

// Texto solto: o link que um marcador escondia na leitura da linha (_https://..._) aparece aqui.
const htmlDoTexto = texto =>
  pedacosComLinks(texto)
    .map(pedaco => (ehTexto(pedaco) ? escapar(pedaco) : htmlDoLink(pedaco)))
    .join('');

const htmlDoNo = no => {
  if (no.tipo === 'texto') return htmlDoTexto(no.texto);
  if (no.tipo === 'codigo') return `<code>${escapar(no.texto)}</code>`;
  if (no.tipo === 'mono') {
    return `<span class="font-mono whitespace-pre-wrap">${escapar(no.texto)}</span>`;
  }
  if (no.tipo === 'link') return htmlDoLink(no);
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
export const formatarWhatsapp = (texto, opcoes) =>
  lerFormatacao(texto, opcoes).map(htmlDoBloco).join('');
