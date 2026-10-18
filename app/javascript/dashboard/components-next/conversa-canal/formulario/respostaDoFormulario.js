// Formulário do WhatsApp (Flows) na conversa com a cara do canal (#1702).
// A resposta do cliente chega como `interactive.nfm_reply`: `response_json` é o que
// o formulário devolveu, com as chaves que quem montou o formulário escolheu. Aqui ela
// vira linhas "rótulo: valor" legíveis, sem JSON cru.
//
// O construtor de formulários da Meta (Flow Builder) gera chaves como
// `screen_0_Nome_completo_0` e valores de escolha como `0_Opção_A`. Isso é formato de
// máquina, não texto de pessoa: tiramos o prefixo `screen_<n>_`, o sufixo `_<n>` e, só
// nessas chaves, o `<n>_` da frente dos valores. Arquivo enviado (foto/documento) chega
// como objeto com `file_name`: mostramos só o nome.
import { MESSAGE_TYPES } from '../../message/constants';

// O token de correlação nunca aparece para o atendente.
const CHAVES_OCULTAS = ['flow_token'];
const PREFIXO_DO_CONSTRUTOR = 'screen';
export const VAZIO = '—';

const soDigitos = texto =>
  texto.length > 0 && [...texto].every(c => c >= '0' && c <= '9');

const ehObjeto = valor =>
  Boolean(valor) && typeof valor === 'object' && !Array.isArray(valor);

const doConstrutor = chave => {
  const partes = chave.split('_');
  return (
    partes.length > 2 &&
    partes[0] === PREFIXO_DO_CONSTRUTOR &&
    soDigitos(partes[1])
  );
};

// `nomeCompleto`, `nome_completo` e `nome-completo` viram "Nome completo".
const palavrasDe = chave =>
  [...chave]
    .map((letra, indice) => {
      if (letra === '_' || letra === '-') return ' ';
      const maiuscula =
        letra !== letra.toLowerCase() && letra === letra.toUpperCase();
      return maiuscula && indice > 0 ? ` ${letra.toLowerCase()}` : letra;
    })
    .join('')
    .split(' ')
    .filter(Boolean)
    .join(' ');

export const rotuloDoCampo = chave => {
  let partes = chave.split('_');
  if (doConstrutor(chave)) {
    partes = partes.slice(2);
    if (partes.length > 1 && soDigitos(partes[partes.length - 1])) {
      partes = partes.slice(0, -1);
    }
  }
  const texto = palavrasDe(partes.join('_'));
  return texto ? texto[0].toUpperCase() + texto.slice(1) : chave;
};

// `0_Opção_A` → "Opção A" (só nas chaves do construtor da Meta).
const semIdDoConstrutor = texto => {
  const [primeira, ...resto] = texto.split('_');
  if (!resto.length || !soDigitos(primeira)) return texto;
  return resto.join(' ');
};

const textoDoValor = (valor, textos, construtor) => {
  if (valor === null || valor === undefined || valor === '') return VAZIO;
  if (typeof valor === 'boolean') return valor ? textos.sim : textos.nao;
  if (typeof valor === 'string') {
    return construtor ? semIdDoConstrutor(valor) : valor;
  }
  if (Array.isArray(valor)) {
    const itens = valor
      .map(item => textoDoValor(item, textos, construtor))
      .filter(item => item !== VAZIO);
    return itens.length ? itens.join(', ') : VAZIO;
  }
  if (ehObjeto(valor)) {
    if (typeof valor.file_name === 'string') return valor.file_name;
    const pares = Object.entries(valor).map(
      ([chave, item]) =>
        `${rotuloDoCampo(chave)}: ${textoDoValor(item, textos, construtor)}`
    );
    return pares.length ? pares.join(' · ') : VAZIO;
  }
  return String(valor);
};

/**
 * @param {unknown} resposta - `response_json` como foi gravado (objeto; texto se a Meta mandou algo ilegível)
 * @param {{ sim: string, nao: string }} textos - como escrever verdadeiro/falso
 * @returns {{ chave: string, rotulo: string, valor: string }[] | null} null quando não dá para ler os campos
 */
export const camposDaResposta = (resposta, textos) => {
  if (!ehObjeto(resposta)) return null;
  return Object.entries(resposta)
    .filter(([chave]) => !CHAVES_OCULTAS.includes(chave))
    .map(([chave, valor]) => ({
      chave,
      rotulo: rotuloDoCampo(chave),
      valor: textoDoValor(valor, textos, doConstrutor(chave)),
    }));
};

const respondeAo = (mensagem, idDoFormulario) =>
  mensagem?.message_type === MESSAGE_TYPES.INCOMING &&
  mensagem.content_attributes?.in_reply_to === idDoFormulario &&
  Boolean(mensagem.content_attributes?.whatsapp_flow_response);

// A resposta mais recente ao formulário `idDoFormulario`, entre as mensagens carregadas
// da conversa (como a loja guarda: chaves snake_case). Só enxerga o que está na tela.
// Anda de trás para frente sem copiar a lista: a resposta costuma estar no fim.
export const respostaDoFormularioPara = (idDoFormulario, mensagens) => {
  if (!Array.isArray(mensagens)) return null;
  for (let indice = mensagens.length - 1; indice >= 0; indice -= 1) {
    if (respondeAo(mensagens[indice], idDoFormulario)) return mensagens[indice];
  }
  return null;
};

// Nome do formulário que originou a resposta (a citação traz a mensagem enviada,
// com as chaves de dentro em snake_case ou camelCase, conforme quem carregou).
export const nomeDoFormulario = mensagemOriginal => {
  const atributos =
    mensagemOriginal?.contentAttributes ?? mensagemOriginal?.content_attributes;
  const rico = atributos?.richMessage ?? atributos?.rich_message;
  if (rico?.type !== 'flow' || typeof rico.name !== 'string') return '';
  return rico.name.trim();
};
