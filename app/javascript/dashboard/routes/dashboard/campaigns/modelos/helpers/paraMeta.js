// Rascunho da tela → corpo que a API de Modelos (#1330) manda para a Meta:
// { name, language, category, parameter_format, components, friendly_name,
//   fields, header_media }. `fields` guarda qual campo ocupa cada número
// ({ '1': 'cliente.primeiro_nome' }), para a campanha ligar as variáveis sem
// adivinhar. Sem expressão regular (regra do Rodrigo).
import { campoParaPerfil } from './campos';
import { ordenarBotoes } from './regraEstrutural';

export const IDIOMA = 'pt_BR';

export const CATEGORIA = {
  aviso: 'UTILITY',
  divulgacao: 'MARKETING',
  codigo: 'AUTHENTICATION',
};

const TOPO_NA_META = { foto: 'IMAGE', video: 'VIDEO', documento: 'DOCUMENT' };
const LETRAS = 'abcdefghijklmnopqrstuvwxyz0123456789';
const MAXIMO_DO_NOME = 512;

// O que a campanha já sabe enviar hoje (auditoria de campanhas, §2): texto,
// mídia no topo, botão de site e botões sem parâmetro. Carrossel, oferta,
// copiar código, catálogo, código de verificação e formulário ainda não.
export const podeIrEmCampanha = modelo => {
  const { formato = 'padrao', botoes = [] } = modelo.conteudo;
  return (
    formato === 'padrao' &&
    !botoes.some(botao => botao.tipo === 'copiar_codigo')
  );
};

// "Pesquisa de satisfação" → "pesquisa_de_satisfacao", o nome que a Meta aceita.
export const nomeParaWhatsapp = nome =>
  (nome || '')
    .normalize('NFD')
    .split('')
    .filter(letra => letra.charCodeAt(0) < 0x300 || letra.charCodeAt(0) > 0x36f)
    .join('')
    .toLowerCase()
    .split('')
    .map(letra => (LETRAS.includes(letra) ? letra : '_'))
    .join('')
    .split('_')
    .filter(Boolean)
    .join('_')
    .slice(0, MAXIMO_DO_NOME);

const botaoNaMeta = botao => {
  if (botao.tipo === 'site') {
    // Final variável ({{1}}) só vem de modelo feito fora da tela: vai com o exemplo.
    const variavel = (botao.valor || '').includes('{{');
    return {
      type: 'URL',
      text: botao.texto,
      url: botao.valor,
      ...(variavel ? { example: [botao.exemplo] } : {}),
    };
  }
  if (botao.tipo === 'ligar') {
    return {
      type: 'PHONE_NUMBER',
      text: botao.texto,
      phone_number: botao.valor,
    };
  }
  if (botao.tipo === 'copiar_codigo') {
    return { type: 'COPY_CODE', example: botao.valor };
  }
  return { type: 'QUICK_REPLY', text: botao.texto };
};

const botoesNaMeta = botoes =>
  botoes.length
    ? [{ type: 'BUTTONS', buttons: ordenarBotoes(botoes).map(botaoNaMeta) }]
    : [];

// Corpo com {{1}}, {{2}}… na ordem em que cada campo aparece, os exemplos e o
// mapa número → campo. Modelo feito fora da tela com variáveis nomeadas
// ({{primeiro_nome}}) continua nomeado: `nomes` (campo → nome original) faz o
// corpo voltar com os mesmos nomes, nunca com números.
const exemploDoCorpo = (ordem, conteudo, nomes) => {
  if (!ordem.length) return {};
  if (!nomes) {
    return {
      example: {
        body_text: [ordem.map(campo => conteudo.exemplos[campo] || '')],
      },
    };
  }
  return {
    example: {
      body_text_named_params: ordem.map(campo => ({
        param_name: nomes[campo] || campo,
        example: conteudo.exemplos[campo] || '',
      })),
    },
  };
};

export const corpoComNumeros = (conteudo, { nomes } = {}) => {
  const ordem = [];
  const chaveDe = campo =>
    nomes ? nomes[campo] || campo : String(ordem.indexOf(campo) + 1);
  const texto = conteudo.texto
    .map(pedaco => {
      if (pedaco.t !== 'campo') return pedaco.v;
      if (!ordem.includes(pedaco.v)) ordem.push(pedaco.v);
      return `{{${chaveDe(pedaco.v)}}}`;
    })
    .join('');
  const corpo = {
    type: 'BODY',
    text: texto,
    ...exemploDoCorpo(ordem, conteudo, nomes),
  };
  const fields = Object.fromEntries(
    ordem
      .map(campo => [chaveDe(campo), campoParaPerfil(campo)])
      .filter(([, valor]) => valor)
  );
  return { corpo, fields };
};

// Topo com arquivo: o handle do arquivo que acabou de subir. Sem arquivo novo
// (alterar), vai sem handle: o handle antigo expira, e o servidor sobe de novo o
// arquivo guardado no perfil (Whatsapp::Templates::HeaderMedia).
const topoNaMeta = (topo, midia) => {
  if (topo?.tipo === 'texto') return [topo.componente];
  const formato = TOPO_NA_META[topo?.tipo];
  if (!formato) return [];
  if (!midia?.handle) return [{ type: 'HEADER', format: formato }];
  return [
    {
      type: 'HEADER',
      format: formato,
      example: { header_handle: [midia.handle] },
    },
  ];
};

const cartoesNaMeta = (cartoes, midias = []) => ({
  type: 'CAROUSEL',
  cards: cartoes.map((cartao, indice) => ({
    components: [
      {
        type: 'HEADER',
        format: cartao.midia === 'video' ? 'VIDEO' : 'IMAGE',
        example: { header_handle: [midias[indice]?.handle || cartao.handle] },
      },
      { type: 'BODY', text: cartao.texto },
      ...botoesNaMeta(cartao.botoes),
    ],
  })),
});

const ofertaNaMeta = oferta => [
  {
    type: 'LIMITED_TIME_OFFER',
    limited_time_offer: { text: oferta.titulo, has_expiration: true },
  },
];

const botoesDaOferta = (oferta, textoDoBotao) => [
  {
    type: 'BUTTONS',
    buttons: [
      ...(oferta.cupom ? [{ type: 'COPY_CODE', example: oferta.cupom }] : []),
      { type: 'URL', text: textoDoBotao, url: oferta.link },
    ],
  },
];

const codigoNaMeta = codigo => [
  {
    type: 'BODY',
    add_security_recommendation: Boolean(codigo.avisoDeSeguranca),
  },
  { type: 'FOOTER', code_expiration_minutes: Number(codigo.validade) },
  { type: 'BUTTONS', buttons: [{ type: 'OTP', otp_type: 'COPY_CODE' }] },
];

// `midias`: { topo, cartoes: [] } com o que subiu agora (handle, blob_signed_id…).
// `textos.botaoDaOferta`: o texto do botão da oferta, no idioma da tela.
export const componentesNaMeta = (
  conteudo,
  { midias = {}, textos = {}, nomes } = {}
) => {
  const formato = conteudo.formato || 'padrao';
  if (formato === 'codigo')
    return { components: codigoNaMeta(conteudo.codigo), fields: {} };
  const { corpo, fields } = corpoComNumeros(conteudo, { nomes });
  if (formato === 'carrossel') {
    return {
      components: [corpo, cartoesNaMeta(conteudo.cartoes, midias.cartoes)],
      fields,
    };
  }
  if (formato === 'oferta') {
    return {
      components: [
        ...topoNaMeta(conteudo.topo, midias.topo),
        ...ofertaNaMeta(conteudo.oferta),
        corpo,
        ...botoesDaOferta(conteudo.oferta, textos.botaoDaOferta),
      ],
      fields,
    };
  }
  return {
    components: [
      ...topoNaMeta(conteudo.topo, midias.topo),
      corpo,
      ...(conteudo.rodape ? [{ type: 'FOOTER', text: conteudo.rodape }] : []),
      ...botoesNaMeta(conteudo.botoes),
    ],
    fields,
  };
};

// Corpo do POST de criação.
export const corpoParaCriar = (rascunho, opcoes = {}) => {
  const { components, fields } = componentesNaMeta(rascunho.conteudo, opcoes);
  const topo = opcoes.midias?.topo;
  return {
    name: nomeParaWhatsapp(rascunho.nome) || `modelo_${Date.now()}`,
    // O idioma do texto: o da tela para os prontos, o do original na cópia.
    language: rascunho.idioma || IDIOMA,
    category: CATEGORIA[rascunho.tipo] || CATEGORIA.aviso,
    parameter_format: 'positional',
    components,
    friendly_name: rascunho.nome.trim(),
    fields,
    ...(topo ? { header_media: topo } : {}),
  };
};

// Variáveis nomeadas do original: campo da tela → nome que a Meta conhece.
const nomesDoModelo = modelo =>
  modelo.formatoDosCampos === 'named'
    ? Object.fromEntries(
        Object.entries(modelo.campos || {}).map(([nome, campo]) => [
          campo,
          nome,
        ])
      )
    : undefined;

// Corpo do PATCH de alteração: a Meta não deixa trocar nome nem idioma; o tipo
// só vai quando a pessoa mudou. Sem mudança no conteúdo nem no tipo (só o nome
// amigável), nada vai para a Meta: o modelo não volta para análise nem gasta
// uma das alterações do mês.
export const corpoParaAlterar = (rascunho, modelo, opcoes = {}) => {
  const mudouOTipo = rascunho.tipo !== modelo.tipo;
  const mudouOConteudo =
    mudouOTipo ||
    Boolean(opcoes.midias?.topo) ||
    JSON.stringify(rascunho.conteudo) !== JSON.stringify(modelo.conteudo);
  const { components, fields } = componentesNaMeta(rascunho.conteudo, {
    ...opcoes,
    nomes: nomesDoModelo(modelo),
  });
  const topo = opcoes.midias?.topo;
  return {
    ...(mudouOConteudo ? { components } : {}),
    friendly_name: rascunho.nome.trim(),
    fields,
    ...(mudouOTipo ? { category: CATEGORIA[rascunho.tipo] } : {}),
    ...(topo ? { header_media: topo } : {}),
  };
};
