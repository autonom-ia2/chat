// #2897 — a cotação dentro da renovação de um seguro: em que estado ela está,
// um de cada vez, e se a renovação já terminou. Funções puras: devolvem o nome
// do estado; quem desenha traduz e põe o botão. A ordem importa: o que já saiu
// vem antes de tudo. O que impede a proposta de chegar à pessoa (sem telefone,
// não quer mensagens, bloqueada, o envio sozinho que não saiu) só fala quando
// há o que enviar: antes disso a cotação continua à vista, com o passo dela.
import { DESFECHOS } from './situacaoDaRenovacao';

export const COTACAO = {
  ENVIADA_SOZINHA: 'ENVIADA_SOZINHA',
  ENVIADA_POR_VOCE: 'ENVIADA_POR_VOCE',
  ENVIADA_POR: 'ENVIADA_POR',
  SEM_TELEFONE: 'SEM_TELEFONE',
  NAO_QUER: 'NAO_QUER',
  BLOQUEADO: 'BLOQUEADO',
  NAO_SAIU: 'NAO_SAIU',
  PRECO_SEM_PDF: 'PRECO_SEM_PDF',
  PRONTA: 'PRONTA',
  PARCIAL: 'PARCIAL',
  COTANDO: 'COTANDO',
  AGGER_FORA: 'AGGER_FORA',
  DEMOROU: 'DEMOROU',
  FALHOU: 'FALHOU',
  FALTOU_PERGUNTADO: 'FALTOU_PERGUNTADO',
  FALTOU_SEM_AGENTE: 'FALTOU_SEM_AGENTE',
  NAO_COTA: 'NAO_COTA',
  NAO_COMECOU: 'NAO_COMECOU',
};

export const FIM = { RENOVOU: 'renovou', NAO_RENOVOU: 'nao_renovou' };
const ETAPA_RENOVADO = 'Renovado';

// Como a renovação terminou: '' enquanto ainda anda.
export const fimDaRenovacao = (renovacao = {}) => {
  if (renovacao?.desfecho === DESFECHOS.NAO_RENOVOU) return FIM.NAO_RENOVOU;
  return renovacao?.etapa === ETAPA_RENOVADO ? FIM.RENOVOU : '';
};

const PAROU = {
  agger_fora: COTACAO.AGGER_FORA,
  demorou: COTACAO.DEMOROU,
  falhou: COTACAO.FALHOU,
};

const enviada = proposta => {
  if (proposta.enviadaSozinha) return COTACAO.ENVIADA_SOZINHA;
  return proposta.enviadaPor?.papel
    ? COTACAO.ENVIADA_POR_VOCE
    : COTACAO.ENVIADA_POR;
};

// A conta cota este seguro sozinha? Precisa da chave da cotação e, quando a
// conta diz quais tipos cota, de o tipo do seguro estar entre eles.
export const cotaEsteSeguro = (
  seguro,
  { cotaSozinha = false, tiposQueCota = null } = {}
) => cotaSozinha && (!tiposQueCota || tiposQueCota.includes(seguro?.tipo));

// Antes de sair: o que a cotação já tem, do mais adiantado ao que nem começou.
// `faltou` é a lista dos dados que faltam para cotar (vazia = não falta nada).
const antesDeEnviar = (renovacao, cotaSozinha) => {
  const { proposta, respostas, cotando, parou, faltou, perguntou } = renovacao;
  if (proposta) return proposta.semPdf ? COTACAO.PRECO_SEM_PDF : COTACAO.PRONTA;
  if (respostas) return COTACAO.PARCIAL;
  if (cotando) return COTACAO.COTANDO;
  if (PAROU[parou]) return PAROU[parou];
  if (faltou?.length) {
    return perguntou ? COTACAO.FALTOU_PERGUNTADO : COTACAO.FALTOU_SEM_AGENTE;
  }
  return cotaSozinha ? COTACAO.NAO_COMECOU : COTACAO.NAO_COTA;
};

// O que espera alguém apertar Enviar: a proposta pronta ou, quando o PDF não
// veio, só o preço.
const ESPERAM_ENVIO = [COTACAO.PRONTA, COTACAO.PRECO_SEM_PDF];

// O que impede a proposta pronta de chegar: sem telefone, pediu para não
// receber, bloqueada (a mesma ordem da regra de envio da casa) ou o envio
// sozinho que o WhatsApp não deixou sair. `null` = nada impede.
const oQueImpede = (pessoa, proposta) => {
  if (!pessoa?.phone_number) return COTACAO.SEM_TELEFONE;
  if (pessoa.opted_out_at) return COTACAO.NAO_QUER;
  if (pessoa.blocked) return COTACAO.BLOQUEADO;
  return proposta.naoSaiuEm ? COTACAO.NAO_SAIU : null;
};

// `null` quando não há cotação a mostrar (sem renovação, ou ela já terminou).
// `daConta`: { cotaSozinha, tiposQueCota }.
export const cotacaoDoCard = (seguro, daConta = {}) => {
  const { renovacao, pessoa } = seguro ?? {};
  if (!renovacao || fimDaRenovacao(renovacao)) return null;
  if (renovacao.proposta?.enviadaEm) return enviada(renovacao.proposta);
  const estado = antesDeEnviar(renovacao, cotaEsteSeguro(seguro, daConta));
  if (!ESPERAM_ENVIO.includes(estado)) return estado;
  return oQueImpede(pessoa, renovacao.proposta) ?? estado;
};

// As respostas das seguradoras, cada uma no seu grupo: quem já deu preço, quem
// ainda não respondeu, quem recusou e a que está sem senha no Agger.
const deuPreco = resposta => resposta.valor !== null;
export const respostasEmGrupos = (respostas = []) => {
  const semPreco = respostas.filter(resposta => !deuPreco(resposta));
  return {
    deram: respostas.filter(deuPreco),
    caladas: semPreco.filter(
      resposta => !resposta.recusou && !resposta.faltaSenha
    ),
    recusaram: semPreco.filter(resposta => resposta.recusou),
    semSenha: semPreco.filter(
      resposta => !resposta.recusou && resposta.faltaSenha
    ),
  };
};

// Alguma seguradora ainda pode responder? Depois do prazo, mais nenhuma: quem
// ficou calada "não respondeu a tempo".
export const aguardaRespostas = ({ respostas, passouOPrazo } = {}) =>
  !passouOPrazo && respostasEmGrupos(respostas).caladas.length > 0;

// Quantas seguradoras já deram preço e quantas ainda não responderam.
export const contarRespostas = (respostas = []) => {
  const { deram, caladas } = respostasEmGrupos(respostas);
  return { deram: deram.length, faltam: caladas.length };
};
