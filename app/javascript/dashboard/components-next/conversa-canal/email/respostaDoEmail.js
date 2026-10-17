// O que cada ação do fim da conversa de e-mail (#1786) põe na caixa de resposta:
// Responder = só quem escreveu; Responder a todos = quem escreveu em Para e os demais
// em Cc (a mesma regra do Chatwoot, getRecipients); Encaminhar = destinatário em
// branco e o e-mail original citado no texto. O envio é o de sempre.
import { getRecipients } from '@chatwoot/utils';
import { MODOS_DE_RESPOSTA } from './useConversaDeEmail';
import { dataCompletaDoEmail } from './dadosDoEmail';

// A data do e-mail original como a pessoa lê, no fuso da conta (sem o "há 1 dia").
const dataLegivel = ({ data, fuso, idioma }) => {
  const quando = Date.parse(data) / 1000;
  if (!Number.isFinite(quando)) return String(data);
  return dataCompletaDoEmail({ quando, agora: quando, fuso, idioma });
};

const juntar = lista => (lista || []).join(', ');

const linhasDoEncaminhado = ({ mensagem, t, formatarData }) => {
  const dados = mensagem?.content_attributes?.email || {};
  const texto =
    dados.text_content?.reply || dados.text_content?.full || mensagem?.content;
  return [
    t('CONVERSA_CANAL.EMAIL.ENCAMINHADA'),
    dados.from?.length
      ? `${t('CONVERSA_CANAL.EMAIL.DE')}: ${juntar(dados.from)}`
      : '',
    dados.date
      ? `${t('CONVERSA_CANAL.EMAIL.DATA')}: ${formatarData(dados.date)}`
      : '',
    dados.subject
      ? `${t('CONVERSA_CANAL.EMAIL.ASSUNTO')}: ${dados.subject}`
      : '',
    dados.to?.length
      ? `${t('CONVERSA_CANAL.EMAIL.PARA')}: ${juntar(dados.to)}`
      : '',
    '',
    String(texto || '').trim(),
  ].filter((linha, i, todas) => linha || todas[i - 1]);
};

export const montarRespostaDoEmail = ({
  modo,
  mensagem,
  contato,
  caixa,
  t,
  fuso,
  idioma = 'pt-BR',
}) => {
  const formatarData = data => dataLegivel({ data, fuso, idioma });
  if (modo === MODOS_DE_RESPOSTA.ENCAMINHAR) {
    return {
      para: '',
      cc: '',
      cco: '',
      texto: `\n\n${linhasDoEncaminhado({ mensagem, t, formatarData }).join('\n')}`,
    };
  }
  const { to, cc, bcc } = getRecipients(
    mensagem,
    contato || '',
    caixa?.email || '',
    caixa?.forward_to_email || ''
  );
  if (modo === MODOS_DE_RESPOSTA.TODOS) {
    return { para: juntar(to), cc: juntar(cc), cco: juntar(bcc), texto: '' };
  }
  return { para: juntar(to), cc: '', cco: '', texto: '' };
};
