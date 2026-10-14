// Rascunho da tela → corpo que a API de Modelos (#1330) manda para a Meta:
// { name, language, category, parameter_format, components, friendly_name,
//   fields, header_media }. `fields` guarda qual campo ocupa cada número
// ({ '1': 'cliente.primeiro_nome' }), para a campanha ligar as variáveis sem
// adivinhar. Sem expressão regular (regra do Rodrigo).
import { campoParaPerfil, semFonteNaCampanha } from './campos';
import { formatoQueNaoVai } from './formatoNaCampanha';
import { ajustarEspacosDosCampos } from './conteudo';
import { ordenarBotoes, telefoneNaMeta } from './regraEstrutural';

export const IDIOMA = 'pt_BR';

export const CATEGORIA = {
  aviso: 'UTILITY',
  divulgacao: 'MARKETING',
  codigo: 'AUTHENTICATION',
};

const TOPO_NA_META = { foto: 'IMAGE', video: 'VIDEO', documento: 'DOCUMENT' };
const LETRAS = 'abcdefghijklmnopqrstuvwxyz0123456789';
const MAXIMO_DO_NOME = 512;

// O que a campanha envia (#1334): todos os formatos, menos código de
// verificação e produtos escolhidos do catálogo (formatoQueNaoVai).
// `opcoes.comCatalogo` (#1418): a conta do WhatsApp tem catálogo de produtos.
export const podeIrEmCampanha = (modelo, opcoes = {}) =>
  modelo.template
    ? !formatoQueNaoVai(modelo.template, opcoes)
    : modelo.conteudo?.formato !== 'codigo';

// Vai em campanha de verdade: formato que a campanha envia e nenhum campo sem
// fonte (como a data e hora do agendamento, num modelo do sistema).
export const usavelEmCampanha = (modelo, opcoes = {}) =>
  podeIrEmCampanha(modelo, opcoes) &&
  !Object.values(modelo.campos || {}).some(semFonteNaCampanha);

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
      url: (botao.valor || '').trim(),
      ...(variavel ? { example: [botao.exemplo] } : {}),
    };
  }
  if (botao.tipo === 'ligar') {
    return {
      type: 'PHONE_NUMBER',
      text: botao.texto,
      phone_number: telefoneNaMeta(botao.valor),
    };
  }
  if (botao.tipo === 'copiar_codigo') {
    return { type: 'COPY_CODE', example: botao.valor };
  }
  return { type: 'QUICK_REPLY', text: botao.texto };
};

// O texto vai sem espaço nas pontas: é o que a conferência mediu (até 25 letras).
const botaoLimpo = botao => ({ ...botao, texto: (botao.texto || '').trim() });

const botoesNaMeta = botoes =>
  botoes.length
    ? [
        {
          type: 'BUTTONS',
          buttons: ordenarBotoes(botoes).map(botaoLimpo).map(botaoNaMeta),
        },
      ]
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
        param_name: nomes[campo] || nomeParaWhatsapp(campo),
        example: conteudo.exemplos[campo] || '',
      })),
    },
  };
};

export const corpoComNumeros = (conteudo, { nomes } = {}) => {
  const ordem = [];
  // Campo novo num modelo nomeado ganha um nome que a Meta aceita (minúsculas,
  // números e _), feito como o nome do modelo.
  const chaveDe = campo =>
    nomes
      ? nomes[campo] || nomeParaWhatsapp(campo)
      : String(ordem.indexOf(campo) + 1);
  const texto = ajustarEspacosDosCampos(conteudo.texto)
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
// arquivo guardado no perfil (Whatsapp::Templates::StoredMedia).
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

// A contagem do tempo que falta (has_expiration) vai junto com o cupom. A data
// de fim não é do modelo: a Meta a recebe em cada envio (expiration_time_ms),
// que a campanha ainda não faz. Sem cupom, a oferta vai só com o título em
// destaque, que a Meta aceita em qualquer leitura da regra.
const ofertaNaMeta = oferta => [
  {
    type: 'LIMITED_TIME_OFFER',
    limited_time_offer: {
      text: oferta.titulo,
      has_expiration: Boolean(oferta.cupom),
    },
  },
];

const botoesDaOferta = (oferta, textoDoBotao) => [
  {
    type: 'BUTTONS',
    buttons: [
      ...(oferta.cupom ? [{ type: 'COPY_CODE', example: oferta.cupom }] : []),
      // O texto do botão do original volta como estava; num modelo novo, o da tela.
      {
        type: 'URL',
        text: oferta.botao || textoDoBotao,
        url: (oferta.link || '').trim(),
      },
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

// Arquivo de cada cartão que subiu agora, com a posição dele (#1334): o
// servidor guarda no perfil e a campanha do carrossel usa a mesma mídia.
export const cardMedia = (cartoes = []) =>
  (cartoes || []).flatMap((midia, indice) =>
    midia?.blob_signed_id
      ? [{ card_index: indice, blob_signed_id: midia.blob_signed_id }]
      : []
  );

const comCartoes = midias => {
  const lista = cardMedia(midias?.cartoes);
  return lista.length ? { card_media: lista } : {};
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
    ...comCartoes(opcoes.midias),
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

// Corpo do PATCH de alteração: a Meta não deixa trocar nome, idioma nem tipo
// (#1394: recusou a troca de tipo até num recusado), então a categoria nunca
// vai; mudar de tipo é criar um modelo novo. Sem mudança no conteúdo (só o nome
// amigável), nada vai para a Meta: o modelo não volta para análise nem gasta
// uma das alterações do mês.
// Recusado vai sempre de novo: corrigir é pedir outra análise.
export const corpoParaAlterar = (rascunho, modelo, opcoes = {}) => {
  const nomes = nomesDoModelo(modelo);
  const { components, fields } = componentesNaMeta(rascunho.conteudo, {
    ...opcoes,
    nomes,
  });
  // Compara o que iria para a Meta (o fim da oferta, por exemplo, não vai).
  const doOriginal = modelo.conteudo
    ? componentesNaMeta(modelo.conteudo, { textos: opcoes.textos, nomes })
        .components
    : null;
  const mudouOConteudo =
    modelo.situacao === 'recusado' ||
    JSON.stringify(components) !== JSON.stringify(doOriginal);
  const topo = opcoes.midias?.topo;
  return {
    ...(mudouOConteudo ? { components } : {}),
    friendly_name: rascunho.nome.trim(),
    fields,
    ...(topo ? { header_media: topo } : {}),
    ...comCartoes(opcoes.midias),
  };
};
