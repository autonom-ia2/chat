import {
  LIMITE_DO_RODAPE,
  LIMITE_DO_TEXTO,
  LIMITE_DO_TEXTO_DA_OFERTA,
  objetivoPorChave,
} from '../constants';
import { conferirFormato } from './formatos';

// O texto de um modelo é uma lista de pedaços: { t: 'texto', v: 'Olá, ' } ou
// { t: 'campo', v: 'nome_cliente' }. Assim a tela mostra o campo como etiqueta
// ("Nome do cliente") e nunca como {{1}}; a troca para o formato da Meta é do
// adaptador. Nada aqui usa expressão regular (regra do Rodrigo): o texto é lido
// com indexOf/split.

const ABRE = '[';
const FECHA = ']';

// Dois pedaços de texto seguidos viram um só (o editor costuma partir o texto).
export const juntarTextos = pedacos =>
  pedacos.reduce((lista, pedaco) => {
    if (pedaco.t === 'texto' && !pedaco.v) return lista;
    const anterior = lista[lista.length - 1];
    if (pedaco.t === 'texto' && anterior?.t === 'texto') {
      return [...lista.slice(0, -1), { t: 'texto', v: anterior.v + pedaco.v }];
    }
    return [...lista, pedaco];
  }, []);

// "Olá, [nome_cliente]!" → pedaços. Só vira campo o que está entre colchetes e
// é um campo conhecido; o resto continua texto.
export const lerTextoComCampos = (fonte, camposConhecidos) => {
  const pedacos = [];
  let resto = fonte || '';
  while (resto.length) {
    const inicio = resto.indexOf(ABRE);
    const fim = inicio === -1 ? -1 : resto.indexOf(FECHA, inicio);
    if (inicio === -1 || fim === -1) {
      pedacos.push({ t: 'texto', v: resto });
      break;
    }
    const chave = resto.slice(inicio + 1, fim);
    if (camposConhecidos.includes(chave)) {
      if (inicio > 0) pedacos.push({ t: 'texto', v: resto.slice(0, inicio) });
      pedacos.push({ t: 'campo', v: chave });
    } else {
      pedacos.push({ t: 'texto', v: resto.slice(0, fim + 1) });
    }
    resto = resto.slice(fim + 1);
  }
  return juntarTextos(pedacos);
};

export const camposUsados = pedacos => [
  ...new Set(pedacos.filter(p => p.t === 'campo').map(p => p.v)),
];

// Pedaços com o valor de exemplo no lugar de cada campo, para a prévia.
export const trocarCamposPorExemplos = (pedacos, exemplos, rotuloDoCampo) =>
  pedacos.map(pedaco =>
    pedaco.t === 'campo'
      ? {
          t: 'exemplo',
          v: exemplos[pedaco.v] || rotuloDoCampo(pedaco.v),
        }
      : pedaco
  );

export const contarLetras = pedacos =>
  pedacos.reduce(
    (total, pedaco) => total + (pedaco.t === 'texto' ? pedaco.v.length : 4),
    0
  );

const temLetras = texto => texto.trim().length > 0;

// Foto, vídeo ou documento no topo precisa de arquivo: o escolhido agora (local)
// ou o que o modelo já tinha na Meta (handle). Título em texto não precisa.
const TOPOS_SEM_ARQUIVO = ['nenhum', 'texto'];
export const topoCompleto = topo =>
  !topo ||
  TOPOS_SEM_ARQUIVO.includes(topo.tipo) ||
  Boolean(topo.local || topo.handle);

// O que pode fazer o WhatsApp recusar, conferido antes de enviar. Só regras de
// forma (onde está o campo, exemplo, tamanho, botões completos): o sentido do
// texto quem julga é o WhatsApp.
export const conferirConteudo = (conteudo, contexto = {}) => {
  // Código de verificação: o texto é fixo do WhatsApp, só a validade muda.
  if (conteudo.formato === 'codigo') return conferirFormato(conteudo, contexto);
  const formato = conteudo.formato || 'padrao';
  const limite =
    formato === 'oferta' ? LIMITE_DO_TEXTO_DA_OFERTA : LIMITE_DO_TEXTO;
  const pedacos = conteudo.texto.filter(
    pedaco => pedaco.t === 'campo' || temLetras(pedaco.v)
  );
  const primeiro = pedacos[0];
  const ultimo = pedacos[pedacos.length - 1];
  const campos = camposUsados(conteudo.texto);
  const seguidos = conteudo.texto.some(
    (pedaco, indice) =>
      pedaco.t === 'campo' &&
      (conteudo.texto[indice + 1]?.t === 'campo' ||
        (conteudo.texto[indice + 1]?.t === 'texto' &&
          !temLetras(conteudo.texto[indice + 1].v) &&
          conteudo.texto[indice + 2]?.t === 'campo'))
  );
  const botaoIncompleto = conteudo.botoes.some(
    botao =>
      !temLetras(botao.texto || '') ||
      (['site', 'ligar'].includes(botao.tipo) && !temLetras(botao.valor || ''))
  );

  const base = [
    { chave: 'TEM_TEXTO', ok: pedacos.some(p => p.t === 'texto') },
    { chave: 'NAO_COMECA_COM_CAMPO', ok: primeiro?.t !== 'campo' },
    { chave: 'NAO_TERMINA_COM_CAMPO', ok: ultimo?.t !== 'campo' },
    { chave: 'CAMPOS_SEPARADOS', ok: !seguidos },
    {
      chave: 'EXEMPLOS',
      ok: campos.every(campo => temLetras(conteudo.exemplos[campo] || '')),
    },
    {
      chave: 'TAMANHO',
      ok: contarLetras(conteudo.texto) <= limite,
      params: { limite },
    },
    ...(['padrao', 'oferta'].includes(formato)
      ? [{ chave: 'TOPO_ARQUIVO', ok: topoCompleto(conteudo.topo) }]
      : []),
    ...(formato === 'padrao'
      ? [
          {
            chave: 'RODAPE',
            ok: (conteudo.rodape || '').length <= LIMITE_DO_RODAPE,
          },
          { chave: 'BOTOES', ok: !botaoIncompleto },
        ]
      : []),
  ];
  return [...base, ...conferirFormato(conteudo, contexto)];
};

export const podeEnviar = (conteudo, contexto) =>
  conferirConteudo(conteudo, contexto).every(item => item.ok);

// Rascunho novo a partir de um objetivo da galeria. `t` é o tradutor do i18n.
export const rascunhoDoObjetivo = (chave, { t, campos }) => {
  const objetivo = objetivoPorChave(chave);
  const base = `MODELOS_WHATSAPP.OBJETIVOS.${objetivo.chave}`;
  const texto =
    objetivo.chave === 'em_branco'
      ? []
      : lerTextoComCampos(t(`${base}.TEXTO`), campos);
  const exemplos = Object.fromEntries(
    camposUsados(texto).map(campo => [
      campo,
      t(`MODELOS_WHATSAPP.CAMPOS.${campo}.EXEMPLO`),
    ])
  );
  return {
    nome: objetivo.chave === 'em_branco' ? '' : t(`${base}.TITULO`),
    objetivo: objetivo.chave,
    biblioteca: Boolean(objetivo.biblioteca),
    tipo: objetivo.tipo,
    numeros: [],
    conteudo: {
      formato: 'padrao',
      topo: { tipo: objetivo.topo || 'nenhum', arquivo: '' },
      texto,
      exemplos,
      rodape: objetivo.rodape ? t(`${base}.RODAPE`) : '',
      botoes: objetivo.botoes.map(botao => ({
        tipo: botao.tipo,
        texto: t(`MODELOS_WHATSAPP.BOTOES_PRONTOS.${botao.chaveTexto}`),
        valor: botao.valor || '',
      })),
    },
  };
};

// Cópia funda e simples de um rascunho, para editar sem mexer no original.
export const copiarRascunho = rascunho => JSON.parse(JSON.stringify(rascunho));
