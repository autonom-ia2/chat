// #2414 G14 (#2630) — o passo "campanha": mandar uma campanha de WhatsApp para
// quem tem as etiquetas, ou marcar o contato como "não recebe". A régua é a do
// servidor (Autonomia::Automacao::PassoDeCampanha): caixa do WhatsApp oficial
// na Cloud API, modelo aprovado de utilidade ou de propaganda, com o corpo
// pedindo {{1}}..{{n}} e nada além do corpo para preencher.
import { serve } from './modeloWhatsapp';

// O modelo serve na campanha pela mesma régua do passo mensagem (utilidade e
// propaganda, lote 5 #2681). O de propaganda mostra o aviso de custo.
export { ehPropaganda } from './modeloWhatsapp';

const CANAL = 'Channel::Whatsapp';
const PROVEDOR = 'whatsapp_cloud';

export const caixasDaCampanha = caixas =>
  (caixas || []).filter(
    caixa => caixa.channel_type === CANAL && caixa.provider === PROVEDOR
  );

export const serveNaCampanha = serve;

export const modelosDaCaixa = caixa =>
  (caixa?.message_templates || []).filter(serveNaCampanha);

// Só o que cada escolha precisa: o "não receber" não leva os campos do disparo.
export const comFaz = (passo, faz) =>
  faz === 'disparar'
    ? { ...passo, faz, etiquetas: passo.etiquetas || [] }
    : { id: passo.id, tipo: passo.tipo, faz };

// Quem recebe (exemplo 7, passo 2): quem tem as etiquetas ou todos os contatos
// da conta. "Todos" não leva etiqueta de público; o "menos quem tem" continua.
export const PARA_TODOS = 'todos';

export const paraTodos = passo => passo?.publico === PARA_TODOS;

export const comPublico = (passo, publico) => {
  if (publico === PARA_TODOS) {
    const { etiquetas, ...resto } = passo;
    return { ...resto, publico: PARA_TODOS };
  }
  const { publico: _, ...resto } = passo;
  return { ...resto, etiquetas: passo.etiquetas || [] };
};

const escrito = texto => typeof texto === 'string' && texto.trim() !== '';

// A caixa e o modelo contra o que a tela mostra: modelo que sumiu da caixa (ou
// caixa que deixou de ser oficial) não salva, como o servidor recusaria.
const modeloNaTela = (passo, caixas) => {
  const caixa = caixasDaCampanha(caixas).find(
    item => item.id === passo.caixa_id
  );
  const chave = `${passo.modelo?.nome}|${passo.modelo?.idioma}`;
  return modelosDaCaixa(caixa).some(
    modelo => `${modelo.name}|${modelo.language}` === chave
  );
};

export const campanhaPronta = (passo, caixas) => {
  if (passo?.faz === 'nao_receber') return true;
  if (passo?.faz !== 'disparar') return false;
  return (
    escrito(passo.titulo) &&
    Number.isInteger(passo.caixa_id) &&
    Boolean(passo.modelo?.nome) &&
    modeloNaTela(passo, caixas) &&
    (passo.modelo.variaveis || []).every(partes =>
      (partes || []).some(escrito)
    ) &&
    (paraTodos(passo) || (passo.etiquetas || []).length > 0)
  );
};

const C = 'AUTOMACAO_LIVRE.CAMPANHA';

// A frase da linha do passo.
export const fraseDaCampanha = (passo, t) =>
  passo.faz === 'disparar'
    ? t(`${C}.FRASE_DISPARAR`, { titulo: passo.titulo || '' })
    : t(`${C}.FRASE_NAO_RECEBER`);
