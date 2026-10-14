import { isWhatsAppComplete } from '@chatwoot/utils';
import {
  COMPONENT_TYPES,
  buildTemplateParameters,
  findComponentByType,
  renderTemplatePreview,
} from 'dashboard/helper/templateHelper';

// #1459 — a mensagem pronta (modelo aprovado pelo WhatsApp) em funções puras:
// o texto com os campos variáveis à vista, os campos a preencher e o formato
// do envio, idêntico ao do preenchedor antigo (WhatsAppTemplateParser).

const ABRE = '{{';
const FECHA = '}}';

// "Olá, {{1}}! Aqui é da {{empresa}}." →
// [{ texto: 'Olá, ' }, { campo: '1' }, { texto: '! Aqui é da ' },
//  { campo: 'empresa' }, { texto: '.' }]
export const partesDoTexto = (texto = '') => {
  const [inicio, ...resto] = texto.split(ABRE);
  const partes = inicio ? [{ texto: inicio }] : [];
  resto.forEach(pedaco => {
    const [campo, ...depois] = pedaco.split(FECHA);
    // "{{" sem o "}}" correspondente não é campo: volta a ser texto.
    if (!depois.length) {
      partes.push({ texto: `${ABRE}${pedaco}` });
      return;
    }
    partes.push({ campo: campo.trim() });
    const sobra = depois.join(FECHA);
    if (sobra) partes.push({ texto: sobra });
  });
  return partes;
};

const PALAVRAS_ANTES = 4;
const PALAVRAS_DEPOIS = 3;

const emUmaLinha = texto => texto.split('\n').join(' ');
const palavrasDe = texto => emUmaLinha(texto).split(' ').filter(Boolean);

// As primeiras `quantas` palavras de um texto que vem logo depois de um
// campo. O que está colado no campo (o "!" de "{{1}}!") vem junto e não conta.
const comecoDoTexto = (texto, quantas) => {
  const colado = !emUmaLinha(texto).startsWith(' ');
  const palavras = palavrasDe(texto);
  const pegas = palavras.slice(0, quantas + (colado ? 1 : 0));
  return {
    texto: `${colado ? '' : ' '}${pegas.join(' ')}`,
    usadas: pegas.length - (colado ? 1 : 0),
    acabou: pegas.length === palavras.length,
  };
};

// O espelho: as últimas `quantas` palavras de um texto que vem logo antes.
const fimDoTexto = (texto, quantas) => {
  const colado = !emUmaLinha(texto).endsWith(' ');
  const palavras = palavrasDe(texto);
  const pegas = palavras.slice(-(quantas + (colado ? 1 : 0)));
  return {
    texto: `${pegas.join(' ')}${colado ? '' : ' '}`,
    usadas: pegas.length - (colado ? 1 : 0),
    acabou: pegas.length === palavras.length,
  };
};

// Anda pelas partes vizinhas de um campo juntando palavras até o limite.
// Outro campo no caminho entra como campo e conta como uma palavra.
const vizinhanca = (partes, limite, cortar) => {
  const juntas = [];
  let faltam = limite;
  partes.every(parte => {
    if (faltam <= 0) return false;
    if (parte.campo) {
      juntas.push({ campo: parte.campo });
      faltam -= 1;
      return true;
    }
    const pedaco = cortar(parte.texto, faltam);
    if (pedaco.texto) juntas.push({ texto: pedaco.texto });
    faltam -= Math.max(pedaco.usadas, 0);
    return pedaco.acabou;
  });
  return juntas;
};

// Pontuação que sobra no começo do trecho quando o corte cai logo depois do
// fim de uma frase (". Seu horário é" → "Seu horário é").
const PONTUACAO_SOLTA = [
  '.',
  ',',
  ';',
  ':',
  '!',
  '?',
  ')',
  ']',
  '…',
  '-',
  '–',
  '—',
  ' ',
];

const semPontuacaoNoComeco = trecho => {
  const [primeira, ...resto] = trecho;
  if (!primeira?.texto) return trecho;
  let comeco = 0;
  while (
    comeco < primeira.texto.length &&
    PONTUACAO_SOLTA.includes(primeira.texto[comeco])
  ) {
    comeco += 1;
  }
  const texto = primeira.texto.slice(comeco);
  return texto ? [{ texto }, ...resto] : resto;
};

// O trecho da mensagem em volta de um campo, para servir de rótulo a quem vai
// preenchê-lo: até 4 palavras antes e 3 depois, com o campo marcado (`alvo`).
// "Olá, {{1}}! Aqui é da Acme." →
// [{ texto: 'Olá, ' }, { campo: '1', alvo: true }, { texto: '! Aqui é da' }]
export const trechoDoCampo = (texto = '', chave = '') => {
  const partes = partesDoTexto(texto);
  const onde = partes.findIndex(parte => parte.campo === chave);
  if (onde < 0) return [];
  const antes = vizinhanca(
    partes.slice(0, onde).reverse(),
    PALAVRAS_ANTES,
    fimDoTexto
  ).reverse();
  const depois = vizinhanca(
    partes.slice(onde + 1),
    PALAVRAS_DEPOIS,
    comecoDoTexto
  );
  return semPontuacaoNoComeco([
    ...antes,
    { campo: chave, alvo: true },
    ...depois,
  ]);
};

// O mesmo trecho em texto corrido, para o leitor de tela: cada campo vira o
// que `falar` devolver ("campo 1").
export const trechoFalado = (trecho, falar) =>
  trecho
    .map((parte, indice) => {
      if (!parte.campo) return parte.texto;
      // Dois campos colados não podem virar uma palavra só.
      const colado = indice > 0 && trecho[indice - 1].campo;
      return `${colado ? ' ' : ''}${falar(parte.campo)}`;
    })
    .join('')
    .trim();

const corpo = modelo => findComponentByType(modelo, COMPONENT_TYPES.BODY);
const cabecalho = modelo => findComponentByType(modelo, COMPONENT_TYPES.HEADER);

export const textoDoCorpo = modelo => corpo(modelo)?.text || '';
const textoDoCabecalho = modelo =>
  cabecalho(modelo)?.format === 'TEXT' ? cabecalho(modelo)?.text || '' : '';

// O preenchedor próprio cobre campos de texto (corpo e cabeçalho de texto).
// Cabeçalho com mídia e botão com variável ficam com o preenchedor antigo.
export const preenchedorProprioCobre = modelo => {
  const params = buildTemplateParameters(modelo);
  const comMidia = params.header && 'media_url' in params.header;
  return !comMidia && !params.buttons;
};

// O exemplo que o próprio modelo traz para cada campo, quando traz.
const exemploDe = (componente, chave, indice, parte) => {
  const exemplos = componente?.example || {};
  const nomeado = [...(exemplos[`${parte}_text_named_params`] || [])].find(
    item => item.param_name === chave
  );
  if (nomeado) return nomeado.example || '';
  const lista = [exemplos[`${parte}_text`] || []].flat(2);
  return lista[indice] || '';
};

// Os campos a preencher, na ordem em que aparecem: cabeçalho e depois corpo.
export const camposDoModelo = modelo => {
  const params = buildTemplateParameters(modelo);
  const daParte = (parte, componente) =>
    Object.keys(params[parte] || {}).map((chave, indice) => ({
      parte,
      chave,
      exemplo: exemploDe(componente, chave, indice, parte),
      trecho: trechoDoCampo(componente?.text || '', chave),
    }));
  return [
    ...daParte('header', cabecalho(modelo)),
    ...daParte('body', corpo(modelo)),
  ];
};

// Os campos do modelo, todos vazios. Nada vem preenchido de antemão: num
// modelo, "{{1}}" pode não ser o nome de quem recebe, e um palpite errado
// sairia para o cliente. Quem ajuda a preencher é o exemplo do próprio modelo.
export const paramsVazios = modelo => buildTemplateParameters(modelo);

export const comCampo = (params, { parte, chave }, valor) => ({
  ...params,
  [parte]: { ...params[parte], [chave]: valor },
});

export const modeloCompleto = (modelo, params) =>
  isWhatsAppComplete(modelo, params);

export const previaDoModelo = (modelo, params) => ({
  cabecalho: renderTemplatePreview(
    textoDoCabecalho(modelo),
    params.header || {}
  ),
  corpo: renderTemplatePreview(textoDoCorpo(modelo), params.body || {}),
});

// O que vai para o servidor: o mesmo formato que o WhatsAppTemplateParser
// emite em `sendMessage` (corpo cru + parâmetros preenchidos).
export const payloadDoModelo = (modelo, params) => {
  const { name, category, language, namespace } = modelo;
  return {
    message: textoDoCorpo(modelo),
    pendingMessageContent: previaDoModelo(modelo, params).corpo,
    templateParams: {
      name,
      category,
      language,
      namespace,
      content_mode: 'raw_template',
      processed_params: params,
    },
  };
};

// Sinais que as telas desenham em volta dos campos. Não são texto traduzível:
// ficam aqui para o template não levar caractere solto.
export const SINAIS = Object.freeze({
  reticencias: '…',
  abreAspas: '“',
  fechaAspas: '”',
  ponto: '·',
  abreParenteses: '(',
  fechaParenteses: ')',
});
