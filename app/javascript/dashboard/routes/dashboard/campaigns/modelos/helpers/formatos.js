import {
  BOTOES_POR_CARTAO,
  CARTOES_MAXIMO,
  CARTOES_MINIMO,
  LIMITE_DO_CARTAO,
  LIMITE_DO_TITULO_DA_OFERTA,
  VALIDADE_MAXIMA,
  VALIDADE_MINIMA,
  formatoPorChave,
} from '../constants';
import { codigoDeExemploValido, problemasDoBotao } from './regraEstrutural';

// Formatos além da mensagem comum: carrossel, oferta por tempo limitado,
// catálogo, código de verificação e botão de formulário. Cada um guarda os
// próprios dados dentro do conteúdo (conteudo.cartoes, conteudo.oferta…).
// Sem expressão regular (regra do Rodrigo).

const DIA_MS = 24 * 60 * 60 * 1000;
const temLetras = texto => (texto || '').trim().length > 0;

// Date → "2026-10-13T18:00", o valor do campo de data e hora do navegador.
export const paraCampoDeData = data => {
  const dois = numero => String(numero).padStart(2, '0');
  return `${data.getFullYear()}-${dois(data.getMonth() + 1)}-${dois(data.getDate())}T${dois(data.getHours())}:${dois(data.getMinutes())}`;
};

// Carrossel é sempre divulgação.
const botaoCompleto = botao =>
  problemasDoBotao(botao, 'divulgacao').length === 0;

const conferirCarrossel = ({ cartoes = [] }) => {
  const assinatura = cartao => cartao.botoes.map(botao => botao.tipo).join(',');
  return [
    {
      chave: 'CARTOES_QUANTIDADE',
      ok: cartoes.length >= CARTOES_MINIMO && cartoes.length <= CARTOES_MAXIMO,
    },
    // Arquivo escolhido agora (local) ou o que o modelo já tinha na Meta (handle).
    {
      chave: 'CARTOES_MIDIA',
      ok: cartoes.every(cartao => cartao.local || cartao.handle),
    },
    {
      chave: 'CARTOES_TEXTO',
      ok: cartoes.every(
        cartao =>
          temLetras(cartao.texto) && cartao.texto.length <= LIMITE_DO_CARTAO
      ),
    },
    {
      chave: 'CARTOES_BOTOES',
      ok: cartoes.every(
        cartao =>
          cartao.botoes.length >= 1 &&
          cartao.botoes.length <= BOTOES_POR_CARTAO &&
          cartao.botoes.every(botaoCompleto)
      ),
    },
    {
      chave: 'CARTOES_IGUAIS',
      ok: cartoes.every(
        cartao => assinatura(cartao) === assinatura(cartoes[0])
      ),
    },
  ];
};

const conferirOferta = ({ oferta }) => [
  {
    chave: 'OFERTA_TITULO',
    ok:
      temLetras(oferta.titulo) &&
      oferta.titulo.length <= LIMITE_DO_TITULO_DA_OFERTA,
  },
  {
    chave: 'OFERTA_FIM',
    ok: Boolean(oferta.terminaEm) && new Date(oferta.terminaEm) > new Date(),
  },
  { chave: 'OFERTA_LINK', ok: temLetras(oferta.link) },
  // Com a contagem regressiva, a Meta exige o botão de copiar o cupom.
  { chave: 'OFERTA_CUPOM', ok: codigoDeExemploValido(oferta.cupom) },
];

export const conferirFormato = (conteudo, { temCatalogo = true } = {}) => {
  if (conteudo.formato === 'carrossel') return conferirCarrossel(conteudo);
  if (conteudo.formato === 'oferta') return conferirOferta(conteudo);
  if (conteudo.formato === 'catalogo') {
    return [{ chave: 'CATALOGO', ok: temCatalogo }];
  }
  if (conteudo.formato === 'codigo') {
    const { validade } = conteudo.codigo;
    return [
      {
        chave: 'VALIDADE',
        ok: validade >= VALIDADE_MINIMA && validade <= VALIDADE_MAXIMA,
      },
    ];
  }
  if (conteudo.formato === 'formulario') {
    return [
      { chave: 'FORMULARIO', ok: Boolean(conteudo.formulario.id) },
      { chave: 'FORMULARIO_BOTAO', ok: temLetras(conteudo.formulario.botao) },
    ];
  }
  return [];
};

// Rascunho novo de um formato. `ler` transforma "Oi, [nome_cliente]!" em
// pedaços (helpers/conteudo.js), `t` é o tradutor do i18n.
export const rascunhoDoFormato = (chave, { t, ler, exemplosDe }) => {
  const formato = formatoPorChave(chave);
  const base = `MODELOS_WHATSAPP.FORMATOS.${chave}`;
  const texto = chave === 'codigo' ? [] : ler(t(`${base}.TEXTO`));
  const conteudo = {
    formato: chave,
    topo: { tipo: 'nenhum', arquivo: '' },
    texto,
    exemplos: exemplosDe(texto),
    rodape: '',
    botoes: [],
  };
  const especifico = {
    carrossel: {
      cartoes: [1, 2].map(numero => ({
        midia: 'foto',
        arquivo: '',
        texto: t(`${base}.CARTAO_${numero}.TEXTO`),
        botoes: [
          {
            tipo: 'site',
            texto: t(`${base}.BOTAO`),
            valor: 'https://hub2you.com.br/novidades',
          },
        ],
      })),
    },
    oferta: {
      oferta: {
        titulo: t(`${base}.TITULO_EXEMPLO`),
        terminaEm: paraCampoDeData(new Date(Date.now() + 2 * DIA_MS)),
        link: 'https://hub2you.com.br/ofertas',
        cupom: t(`${base}.CUPOM_EXEMPLO`),
      },
    },
    catalogo: { catalogo: { botao: t(`${base}.BOTAO`) } },
    codigo: {
      codigo: { botao: 'copiar', validade: 10, avisoDeSeguranca: true },
    },
    formulario: { formulario: { id: '', botao: t(`${base}.BOTAO`) } },
  }[chave];
  return {
    nome: t(`${base}.NOME_PADRAO`),
    objetivo: chave,
    biblioteca: false,
    tipo: formato.tipo,
    numeros: [],
    conteudo: { ...conteudo, ...especifico },
  };
};
