// Modelo da tela → modelo no formato da Meta, o mesmo que a campanha lê de
// `channel.message_templates` (components com {{1}}, {{2}}…). Também devolve
// `campos`: qual etiqueta ("nome_cliente") ocupa cada número, para a campanha
// ligar as variáveis sem adivinhar. Sem expressão regular (regra do Rodrigo).

const SITUACAO_NA_META = {
  pronto: 'APPROVED',
  em_analise: 'PENDING',
  recusado: 'REJECTED',
  pausado: 'PAUSED',
};

const TIPO_NA_META = {
  aviso: 'UTILITY',
  divulgacao: 'MARKETING',
  codigo: 'AUTHENTICATION',
};

const TOPO_NA_META = { foto: 'IMAGE', video: 'VIDEO', documento: 'DOCUMENT' };

const BOTAO_NA_META = botao => {
  if (botao.tipo === 'site') {
    return { type: 'URL', text: botao.texto, url: botao.valor };
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

export const paraTemplateDaMeta = modelo => {
  const { conteudo } = modelo;
  const ordem = [];
  const corpo = conteudo.texto
    .map(pedaco => {
      if (pedaco.t !== 'campo') return pedaco.v;
      if (!ordem.includes(pedaco.v)) ordem.push(pedaco.v);
      return `{{${ordem.indexOf(pedaco.v) + 1}}}`;
    })
    .join('');
  const topo = TOPO_NA_META[conteudo.topo?.tipo];
  const components = [
    ...(topo ? [{ type: 'HEADER', format: topo }] : []),
    {
      type: 'BODY',
      text: corpo,
      ...(ordem.length
        ? {
            example: {
              body_text: [ordem.map(campo => conteudo.exemplos[campo] || '')],
            },
          }
        : {}),
    },
    ...(conteudo.rodape ? [{ type: 'FOOTER', text: conteudo.rodape }] : []),
    ...(conteudo.botoes?.length
      ? [{ type: 'BUTTONS', buttons: conteudo.botoes.map(BOTAO_NA_META) }]
      : []),
  ];
  return {
    template: {
      id: modelo.id,
      name: modelo.nomeNoWhatsapp,
      language: modelo.idioma,
      status: SITUACAO_NA_META[modelo.situacao],
      category: TIPO_NA_META[modelo.tipo] || 'UTILITY',
      components,
    },
    campos: Object.fromEntries(
      ordem.map((campo, indice) => [String(indice + 1), campo])
    ),
  };
};
