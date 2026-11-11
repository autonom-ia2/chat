// #2897 — os ajustes das renovações na demonstração: o que a conta fictícia
// escolheu (o padrão, até alguém salvar), os funis que ela já tem e quem atende
// sozinho. Só é carregado no ambiente de desenvolvimento. O que é salvo fica na
// memória deste módulo e some ao recarregar a página.
import {
  AJUSTES_PADRAO,
  COMO_ENVIA,
  PALAVRAS,
} from '../carteira/ajustesDaRenovacao';

// Funis e etapas inventados, de uma conta qualquer.
export const FUNIS_DA_DEMO = [
  { nome: 'Vendas', etapas: ['Novo contato', 'Em conversa', 'Proposta'] },
  { nome: 'Atendimento', etapas: ['Aberto', 'Em andamento', 'Resolvido'] },
];
// O agente da conta fictícia.
export const AGENTE_DA_DEMO = 'Lia';

// { ajustes, em } — `em` é quando foi salvo (segundos).
let guardados = null;

export const esquecerAjustesDaDemo = () => {
  guardados = null;
};

export const ajustesDaDemo = () => guardados?.ajustes ?? AJUSTES_PADRAO;
export const jaEscolheuNaDemo = () => Boolean(guardados);

export const salvarAjustesNaDemo = (novos, agora = Date.now()) => {
  guardados = {
    ajustes: { ...ajustesDaDemo(), ...novos },
    em: Math.floor(agora / 1000),
  };
  return guardados.ajustes;
};

const podeReceber = pessoa =>
  Boolean(pessoa.phone_number) && !pessoa.opted_out_at;

// "Sai sozinha": a proposta que estava pronta, esperando alguém enviar, já foi.
// Quem está sem telefone ou pediu para não receber mensagens fica de fora.
const comOEnvioSozinho = seguro => {
  const { renovacao } = seguro;
  const esperando = renovacao?.proposta && !renovacao.proposta.enviadaEm;
  if (
    !esperando ||
    ajustesDaDemo().comoEnvia !== COMO_ENVIA.SOZINHA ||
    !podeReceber(seguro.pessoa)
  ) {
    return seguro;
  }
  return {
    ...seguro,
    renovacao: {
      ...renovacao,
      etapa: 'Opções enviadas',
      proposta: {
        ...renovacao.proposta,
        enviadaSozinha: true,
        enviadaEm: guardados.em,
      },
    },
  };
};

// Texto inventado do que o seguro cobre (a leitura de verdade é da entrega).
const COBRE_NA_DEMO = 'batida, roubo e furto, vidros e guincho';
const asDezEMeia = segundos => {
  const dia = new Date(segundos * 1000);
  dia.setHours(10, 30, 0, 0);
  return Math.floor(dia.getTime() / 1000);
};

// "Seu seguro em palavras simples" só existe na apólice nova, e some quando a
// corretora escolheu não mandar. Com "sai sozinho", já foi no dia em que a
// apólice começou.
const comAsPalavras = seguro => {
  if (!seguro.apoliceNova) return seguro;
  const modo = ajustesDaDemo().palavras;
  if (modo === PALAVRAS.NAO_MANDAR) return { ...seguro, palavras: null };
  const sozinho = modo === PALAVRAS.SOZINHO;
  return {
    ...seguro,
    palavras: {
      cobre: COBRE_NA_DEMO,
      texto: '',
      enviadoEm: sozinho ? asDezEMeia(seguro.comeca) : null,
      ...seguro.palavras,
      sozinho,
    },
  };
};

export const comOsAjustes = seguro => comAsPalavras(comOEnvioSozinho(seguro));
