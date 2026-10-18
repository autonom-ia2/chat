// O modelo de WhatsApp que a mensagem usou (#1702), lido do modelo aprovado guardado na
// caixa (`message_templates`) pelo nome e idioma gravados na mensagem. Modelo apagado
// ou renomeado na Meta e sem a foto do envio: nada aparece (o balão fica só com o
// texto, sem espaço vazio).
// Os botões vêm do modelo de hoje; o endereço de cada link vem da foto do envio (#1717).
// Topo (texto, foto, vídeo, documento), rodapé, produto, oferta e a mídia e o texto de
// cada cartão vêm da foto do envio; o modelo de hoje só cobre o que a foto não tem
// (mensagem anterior a ela). Modelo apagado: os botões saem da própria foto.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const ICONE = {
  QUICK_REPLY: 'i-ph-arrow-bend-up-left-bold',
  URL: 'i-ph-arrow-square-out-bold',
  PHONE_NUMBER: 'i-ph-phone-bold',
  VOICE_CALL: 'i-ph-phone-call-bold',
  COPY_CODE: 'i-ph-copy-bold',
  OTP: 'i-ph-copy-bold',
  FLOW: 'i-ph-note-pencil-bold',
  CATALOG: 'i-ph-storefront-bold',
  MPM: 'i-ph-storefront-bold',
  SPM: 'i-ph-storefront-bold',
};
// Botões que o app escreve por conta própria (o modelo não traz o texto).
const TEXTO_DO_APP = {
  COPY_CODE: 'CONVERSA_CANAL.MODELO.COPIAR_CODIGO',
  CATALOG: 'CONVERSA_CANAL.MODELO.VER_CATALOGO',
  MPM: 'CONVERSA_CANAL.MODELO.VER_ITENS',
  SPM: 'CONVERSA_CANAL.MODELO.VER_ITEM',
};
const ICONE_DA_MIDIA = {
  IMAGE: 'i-ph-image',
  VIDEO: 'i-ph-video',
  DOCUMENT: 'i-ph-file-text',
  PRODUCT: 'i-ph-storefront',
};
const PADRAO = 'i-ph-arrow-bend-up-left-bold';
// Tipos de topo de mídia, no formato da foto do envio (minúsculo).
const MIDIAS_DO_TOPO = ['image', 'video', 'document'];
// O servidor guarda o texto do botão na foto do envio com até 40 caracteres.
const TEXTO_MAX = 40;
// O endereço que o cliente abre ao tocar no botão de link (B2, teste do Rodrigo em
// 17/10): o da foto do envio (#1717, `enviado.botoes[i].url`), que o servidor já
// montou com o final variável e validou. Só http(s); o resto não vira link.
// Mensagem anterior à foto do envio não traz o endereço: o botão só mostra.
export const enderecoDoBotao = url => {
  if (typeof url !== 'string' || !url) return '';
  try {
    const { protocol } = new URL(url);
    return ['https:', 'http:'].includes(protocol) ? url : '';
  } catch {
    return '';
  }
};

// O texto de um componente do modelo, só quando não sobrou campo por preencher ({{1}}):
// o atendente nunca vê a chave no lugar do valor.
const textoSemCampo = componente => {
  const texto = componente?.text || '';
  return texto.includes('{{') ? '' : texto;
};

const topoDoEnvio = doEnvio => {
  if (doEnvio?.tipo === 'text') {
    return doEnvio.texto ? { tipo: 'text', texto: doEnvio.texto } : null;
  }
  if (!MIDIAS_DO_TOPO.includes(doEnvio?.tipo)) return null;
  return {
    tipo: doEnvio.tipo,
    url: enderecoDoBotao(doEnvio.url),
    nome: doEnvio.nome || '',
  };
};

// `mensagem`: computed com { additionalAttributes, inboxId }.
export const useModeloDaMensagem = mensagem => {
  const { t } = useI18n();
  const caixaPorId = useMapGetter('inboxes/getInbox');

  const modelo = computed(() => {
    const params = mensagem.value?.additionalAttributes?.templateParams;
    if (!params?.name) return null;
    const modelos = caixaPorId.value(mensagem.value.inboxId)?.message_templates;
    const doNome = (modelos || []).filter(m => m.name === params.name);
    // Com idioma gravado, só o modelo daquele idioma: os botões de outro idioma
    // mostrariam ao atendente algo que o cliente não recebeu. Sem idioma (jornada
    // de campanha grava só o nome), só quando o nome tem um idioma só.
    if (!params.language) return doNome.length === 1 ? doNome[0] : null;
    return doNome.find(m => m.language === params.language) || null;
  });

  const componente = tipo =>
    (modelo.value?.components || []).find(c => c.type === tipo);

  // A foto do envio (#1717): o que a mensagem levou, na posição de cada botão.
  const enviado = computed(
    () => mensagem.value?.additionalAttributes?.templateParams?.enviado || {}
  );

  // O botão da foto do envio é o mesmo de hoje: link nos dois e, quando a foto guarda o
  // texto, o mesmo texto (modelo editado com botões trocados não leva o link do outro).
  const mesmoBotao = (b, enviadoDoBotao) =>
    b.type === 'URL' &&
    enviadoDoBotao?.tipo === 'url' &&
    (!enviadoDoBotao.texto ||
      enviadoDoBotao.texto === (b.text || '').trim().slice(0, TEXTO_MAX));

  const botao = (b, enviadoDoBotao) => ({
    tipo: b.type,
    texto: b.text || (TEXTO_DO_APP[b.type] ? t(TEXTO_DO_APP[b.type]) : ''),
    icone: ICONE[b.type] || PADRAO,
    // O tipo também confere: modelo editado depois do envio não leva o link de outro botão.
    endereco: mesmoBotao(b, enviadoDoBotao)
      ? enderecoDoBotao(enviadoDoBotao.url)
      : '',
  });

  // Botão lido só da foto do envio (modelo apagado ou renomeado na Meta).
  const botaoDoEnvio = b => {
    const tipo = String(b?.tipo || '').toUpperCase();
    return {
      tipo,
      texto: b?.texto || (TEXTO_DO_APP[tipo] ? t(TEXTO_DO_APP[tipo]) : ''),
      icone: ICONE[tipo] || PADRAO,
      endereco: tipo === 'URL' ? enderecoDoBotao(b.url) : '',
    };
  };
  const botoesDoEnvio = lista =>
    (Array.isArray(lista) ? lista : []).map(botaoDoEnvio);

  const botoes = computed(() => {
    if (!modelo.value) return botoesDoEnvio(enviado.value.botoes);
    return (componente('BUTTONS')?.buttons || []).map((b, indice) =>
      botao(b, enviado.value.botoes?.[indice])
    );
  });

  // A mídia do cartão que o cliente recebeu (#1717, `cartoes[i].midia`); sem endereço
  // (arquivo de fora, ou mensagem anterior à foto), o ícone do tipo.
  const midiaDoCartao = (formato, doEnvio) => {
    const tipo = doEnvio?.tipo || String(formato || '').toLowerCase();
    return {
      tipo,
      url: enderecoDoBotao(doEnvio?.url),
      icone: ICONE_DA_MIDIA[tipo.toUpperCase()] || 'i-ph-image',
    };
  };

  const cartoes = computed(() => {
    const doEnvio = enviado.value.cartoes;
    const doModelo = componente('CAROUSEL')?.cards;
    if (!doModelo && Array.isArray(doEnvio)) {
      return doEnvio.map(cartao => ({
        midia: midiaDoCartao('', cartao?.midia),
        texto: cartao?.texto || '',
        botoes: botoesDoEnvio(cartao?.botoes),
      }));
    }
    return (doModelo || []).map((cartao, indiceDoCartao) => {
      const partes = cartao.components || [];
      const foto = doEnvio?.[indiceDoCartao];
      return {
        midia: midiaDoCartao(
          partes.find(c => c.type === 'HEADER')?.format,
          foto?.midia
        ),
        // O texto com os valores enviados; o do modelo só sem campo por preencher.
        texto:
          foto?.texto || textoSemCampo(partes.find(c => c.type === 'BODY')),
        botoes: (partes.find(c => c.type === 'BUTTONS')?.buttons || []).map(
          (b, indice) => botao(b, foto?.botoes?.[indice])
        ),
      };
    });
  });

  // O topo: { tipo: 'text', texto } ou { tipo: 'image'|'video'|'document', url, nome }.
  // Da foto do envio; sem ela, ou foto sem topo (gravada antes de 17/10), o do modelo de
  // hoje, como o rodapé (a mídia só com o ícone: o exemplo guardado na Meta não é o
  // arquivo que o cliente recebeu).
  const topo = computed(() => {
    if (enviado.value.topo) return topoDoEnvio(enviado.value.topo);
    const doModelo = componente('HEADER');
    const tipo = String(doModelo?.format || '').toLowerCase();
    if (tipo === 'text') {
      const texto = textoSemCampo(doModelo);
      return texto ? { tipo, texto } : null;
    }
    return MIDIAS_DO_TOPO.includes(tipo) ? { tipo, url: '', nome: '' } : null;
  });

  // O rodapé cinza: o da foto do envio; foto sem rodapé (gravada antes de 17/10), o do modelo.
  const rodape = computed(
    () => enviado.value.rodape || componente('FOOTER')?.text || ''
  );

  // A foto do envio chega aqui em camelCase: a lista de mensagens (MessageList) converte
  // a mensagem inteira (`expira_em` → `expiraEm`, `retailer_id` → `retailerId`).
  // A oferta: { texto, expiraEm } (expiraEm em segundos, só quando o modelo conta o tempo).
  const oferta = computed(() => {
    const doEnvio = enviado.value.oferta;
    if (doEnvio)
      return { texto: doEnvio.texto || '', expiraEm: doEnvio.expiraEm || 0 };
    const doModelo = componente('LIMITED_TIME_OFFER');
    if (!doModelo) return null;
    return { texto: doModelo.limited_time_offer?.text || '', expiraEm: 0 };
  });

  // O produto do topo (SPM): nome, preço e foto do catálogo na hora do envio; sem a foto
  // do envio, só o cartão genérico.
  const produto = computed(() => {
    const doEnvio = enviado.value.produto;
    if (doEnvio?.retailerId) {
      return {
        nome: doEnvio.nome || '',
        preco: doEnvio.preco || '',
        foto: enderecoDoBotao(doEnvio.fotoUrl),
      };
    }
    return componente('HEADER')?.format === 'PRODUCT'
      ? { nome: '', preco: '', foto: '' }
      : null;
  });

  return { modelo, botoes, cartoes, oferta, produto, topo, rodape };
};
