// O que o "+" da caixa de resposta envia (#1702): o mesmo `rich_message` que o robô
// já manda desde o #1473. O servidor confere tudo e responde o motivo em português;
// aqui se monta o pedido e se conferem, na hora, o obrigatório e os limites da Meta
// (os mesmos de app/services/rich_messages/types), para a recusa não chegar só no envio.
//
// `content` é o texto que o cliente lê e que o histórico (e o agente de IA) guarda.
// Localização e contato não têm texto: o servidor exige `content` vazio para eles.

import { mapHrefOf } from '../../message/bubbles/RichMessage/mapLink';

export const LIMITES = {
  mensagem: 1024,
  mensagemDaLista: 4096,
  nomeDoBotao: 20,
  endereco: 2000,
  opcaoBotao: 20,
  opcaoLista: 24,
  nomeDaLista: 20,
  opcoes: 10,
  botoes: 3,
  nomeDoLugar: 100,
  enderecoDoLugar: 300,
  nomeDoContato: 100,
  textoDoBotao: 30,
  nomeDoFormulario: 60,
  digitosMinimos: 8,
  digitosMaximos: 15,
};

const limpo = texto => String(texto ?? '').trim();

const DIGITOS = '0123456789';
const soDigitos = texto =>
  texto
    .split('')
    .filter(c => DIGITOS.includes(c))
    .join('');

// Decimal simples: sinal opcional, dígitos e no máximo um ponto. Nada de "1e3",
// "0x10" ou "Infinity", que o Number() aceitaria.
const ehDecimal = texto => {
  const semSinal = texto.startsWith('-') ? texto.slice(1) : texto;
  const partes = semSinal.split('.');
  return (
    partes.length <= 2 &&
    partes[0] !== '' &&
    partes.every(parte => parte !== '' && soDigitos(parte) === parte)
  );
};

const parDeCoordenadas = texto => {
  const partes = limpo(texto).split(',').map(limpo);
  if (partes.length !== 2 || !partes.every(ehDecimal)) return null;
  const [latitude, longitude] = partes.map(Number);
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return { latitude, longitude };
};

const decodificado = texto => {
  try {
    return decodeURIComponent(texto);
  } catch {
    return texto;
  }
};

const depoisDe = (texto, marca) => {
  const inicio = texto.lastIndexOf(marca);
  if (inicio < 0) return '';
  return texto.slice(inicio + marca.length).split('!')[0];
};

// Dentro de um link do Google Maps, na ordem de precisão: "!3dlat!4dlng" (o ponto do
// lugar), "?q=lat,lng" e por último "/@lat,lng,17z" (só o centro da tela do mapa).
const coordenadasDoLink = endereco => {
  let url;
  try {
    url = new URL(endereco);
  } catch {
    return null;
  }
  const completo = decodificado(url.pathname + url.search);
  const doPonto = parDeCoordenadas(
    `${depoisDe(completo, '!3d')},${depoisDe(completo, '!4d')}`
  );
  if (doPonto) return doPonto;

  const busca = ['q', 'query', 'll']
    .map(chave => url.searchParams.get(chave))
    .find(valor => valor && parDeCoordenadas(valor));
  if (busca) return parDeCoordenadas(busca);

  const trechoComArroba = url.pathname
    .split('/')
    .find(trecho => trecho.startsWith('@'));
  if (!trechoComArroba) return null;
  const [lat, lng] = trechoComArroba.slice(1).split(',');
  return parDeCoordenadas(`${lat},${lng}`);
};

// Aceita "-23.5613, -46.6565" (o que o Google Maps copia ao clicar nos números) ou
// um link do Google Maps com as coordenadas.
export const lerCoordenadas = texto =>
  parDeCoordenadas(texto) || coordenadasDoLink(limpo(texto));

// "+55 11 98765-4321" → "+5511987654321". Sem "+" não adivinha o país nem mexe no
// nono dígito (a base tem números legítimos de 12 dígitos): devolve vazio e a janela
// pede o número como está no WhatsApp, com + e o código do país. De 8 a 15 dígitos.
export const telefoneInternacional = texto => {
  const bruto = limpo(texto);
  if (!bruto.startsWith('+')) return '';
  const digitos = soDigitos(bruto);
  const cabe =
    digitos.length >= LIMITES.digitosMinimos &&
    digitos.length <= LIMITES.digitosMaximos;
  return cabe ? `+${digitos}` : '';
};

const enderecoDeSite = texto => {
  try {
    const url = new URL(limpo(texto));
    return ['http:', 'https:'].includes(url.protocol) && Boolean(url.hostname);
  } catch {
    return false;
  }
};

// Cada erro é { campo: motivo }; o motivo é a chave da frase em JANELA.ERROS.
const conferir = regras =>
  regras.reduce(
    (erros, [campo, motivo, falhou]) =>
      falhou && !erros[campo] ? { ...erros, [campo]: motivo } : erros,
    {}
  );

const vazio = texto => !limpo(texto);
const passa = (texto, maximo) => limpo(texto).length > maximo;

const resultado = (erros, montar) =>
  Object.keys(erros).length ? { erros } : { pedido: montar() };

export const montarBotaoDeLink = campos =>
  resultado(
    conferir([
      ['mensagem', 'mensagem', vazio(campos.mensagem)],
      ['mensagem', 'mensagemLonga', passa(campos.mensagem, LIMITES.mensagem)],
      ['nomeDoBotao', 'nomeDoBotao', vazio(campos.nomeDoBotao)],
      [
        'nomeDoBotao',
        'nomeDoBotaoLongo',
        passa(campos.nomeDoBotao, LIMITES.nomeDoBotao),
      ],
      ['endereco', 'endereco', vazio(campos.endereco)],
      [
        'endereco',
        'enderecoInvalido',
        passa(campos.endereco, LIMITES.endereco) ||
          !enderecoDeSite(campos.endereco),
      ],
    ]),
    () => ({
      content: limpo(campos.mensagem),
      richMessage: {
        type: 'link_button',
        label: limpo(campos.nomeDoBotao),
        url: limpo(campos.endereco),
      },
    })
  );

export const opcoesPreenchidas = opcoes => opcoes.map(limpo).filter(Boolean);

// Até 3 opções viram botões; mais que isso, uma lista que abre por um botão.
export const viraLista = opcoes =>
  opcoesPreenchidas(opcoes).length > LIMITES.botoes;

export const montarOpcoes = campos => {
  const opcoes = opcoesPreenchidas(campos.opcoes || []);
  const lista = viraLista(opcoes);
  const maximoDoTitulo = lista ? LIMITES.opcaoLista : LIMITES.opcaoBotao;
  const maximoDaMensagem = lista ? LIMITES.mensagemDaLista : LIMITES.mensagem;
  const erros = conferir([
    ['mensagem', 'mensagem', vazio(campos.mensagem)],
    ['mensagem', 'mensagemLonga', passa(campos.mensagem, maximoDaMensagem)],
    ['opcoes', 'opcoes', opcoes.length < 2],
    ['opcoes', 'opcoesDemais', opcoes.length > LIMITES.opcoes],
    [
      'opcoes',
      lista ? 'opcaoDaListaLonga' : 'opcaoLonga',
      opcoes.some(opcao => opcao.length > maximoDoTitulo),
    ],
    ['opcoes', 'opcoesRepetidas', new Set(opcoes).size !== opcoes.length],
    ['nomeDaLista', 'nomeDaLista', lista && vazio(campos.nomeDaLista)],
    [
      'nomeDaLista',
      'nomeDaListaLongo',
      lista && passa(campos.nomeDaLista, LIMITES.nomeDaLista),
    ],
  ]);
  return resultado(erros, () => ({
    content: limpo(campos.mensagem),
    richMessage: {
      type: 'options',
      options: opcoes.map((title, indice) => ({
        id: `opcao_${indice + 1}`,
        title,
      })),
      ...(lista ? { button: limpo(campos.nomeDaLista) } : {}),
    },
  }));
};

export const montarLocalizacao = campos => {
  const coordenadas = lerCoordenadas(campos.coordenadas);
  const erros = conferir([
    ['coordenadas', 'coordenadas', !coordenadas],
    ['nome', 'nomeDoLugarLongo', passa(campos.nome, LIMITES.nomeDoLugar)],
    [
      'endereco',
      'enderecoDoLugarLongo',
      passa(campos.endereco, LIMITES.enderecoDoLugar),
    ],
  ]);
  return resultado(erros, () => ({
    content: '',
    richMessage: {
      type: 'location',
      ...coordenadas,
      ...(limpo(campos.nome) ? { name: limpo(campos.nome) } : {}),
      ...(limpo(campos.endereco) ? { address: limpo(campos.endereco) } : {}),
    },
  }));
};

export const montarPedidoDeLocalizacao = campos =>
  resultado(
    conferir([
      ['mensagem', 'mensagem', vazio(campos.mensagem)],
      ['mensagem', 'mensagemLonga', passa(campos.mensagem, LIMITES.mensagem)],
    ]),
    () => ({
      content: limpo(campos.mensagem),
      richMessage: { type: 'location_request' },
    })
  );

export const montarContato = campos =>
  resultado(
    conferir([
      ['nome', 'nome', vazio(campos.nome)],
      ['nome', 'nomeDoContatoLongo', passa(campos.nome, LIMITES.nomeDoContato)],
      ['telefone', 'telefone', !telefoneInternacional(campos.telefone)],
    ]),
    () => {
      const phone = telefoneInternacional(campos.telefone);
      // Com o wa_id (os dígitos do número), o WhatsApp mostra "Conversar" no cartão;
      // sem ele, mostra "Convidar para o WhatsApp" até para quem já usa (teste real de 16/10).
      return {
        content: '',
        richMessage: {
          type: 'contact',
          name: limpo(campos.nome),
          phone,
          wa_id: phone.slice(1),
        },
      };
    }
  );

// Formulário aprovado na Meta (WhatsApp Flows). Abre na primeira tela do formulário
// publicado; o token identifica este envio quando a resposta voltar.
export const montarFormulario = (campos, { tela, token }) => {
  const erros = conferir([
    ['formulario', 'formulario', vazio(campos.formulario) || !tela],
    ['mensagem', 'mensagem', vazio(campos.mensagem)],
    ['mensagem', 'mensagemLonga', passa(campos.mensagem, LIMITES.mensagem)],
    ['textoDoBotao', 'textoDoBotao', vazio(campos.textoDoBotao)],
    [
      'textoDoBotao',
      'textoDoBotaoLongo',
      passa(campos.textoDoBotao, LIMITES.textoDoBotao),
    ],
  ]);
  // O nome só identifica o formulário no painel; acima do limite, vai cortado.
  const nome = limpo(campos.nomeDoFormulario).slice(
    0,
    LIMITES.nomeDoFormulario
  );
  return resultado(erros, () => ({
    content: limpo(campos.mensagem),
    richMessage: {
      type: 'flow',
      flow_id: limpo(campos.formulario),
      cta: limpo(campos.textoDoBotao),
      token,
      screen: tela,
      ...(nome ? { name: nome } : {}),
    },
  }));
};

// O texto que o cliente recebe quando o formato não sai nativo (WAHA): o mesmo que o
// servidor monta (`fallback_text` de cada tipo em app/services/rich_messages/types):
// o corpo, uma linha em branco e o complemento.
const COMPLEMENTO = {
  link_button: rico => `${rico.label}: ${rico.url}`,
  options: rico =>
    rico.options.map((opcao, i) => `${i + 1}. ${opcao.title}`).join('\n'),
  location: rico =>
    [rico.name, rico.address, mapHrefOf(rico.latitude, rico.longitude)]
      .filter(Boolean)
      .join('\n'),
  contact: rico => `${rico.name}: ${rico.phone}`,
  location_request: () => '',
};

export const textoParaQuemNaoTemFormato = pedido => {
  const complemento = COMPLEMENTO[pedido.richMessage.type]?.(
    pedido.richMessage
  );
  return [pedido.content, complemento].filter(Boolean).join('\n\n');
};
