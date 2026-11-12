// #2897 — `?caso=<nome>`: o seguro aberto cai num estado que o exemplo de
// sempre não mostra (fonte/modoCarteira.js tem a lista). Só é carregado no
// ambiente de desenvolvimento. Cada caso diz quando vale e o que muda; nada do
// que chega é alterado. Depois que a pessoa age na renovação (cotar de novo,
// pedir a proposta, enviar), vale o que ela fez e o caso sai de cena.
import { emSegundos, escritaDe } from './carteira';
import { DADOS_PARA_COTAR } from './carteiraPlano';
import { PERIODOS } from '../carteira/periodoDoPreco';

const AUMENTO_DA_PROPOSTA_ANEXADA = 5;
const CENTAVOS = 100;
const MESES_DO_ANO = 12;
const HORA_EM_MS = 60 * 60 * 1000;
const NAO_SAIU_HA_HORAS = 2;

const comAumento = (valor, aumento) =>
  Math.round(valor * (CENTAVOS + aumento)) / CENTAVOS;
const porMes = valor =>
  Math.round((valor / MESES_DO_ANO) * CENTAVOS) / CENTAVOS;

// Seguradoras inventadas que respondem (ou não) a uma cotação: quanto cada uma
// pede em relação ao valor de hoje. Uma delas não tem proposta em PDF.
const RESPOSTAS_DA_COTACAO = [
  { nome: 'Seguradora Atlântica', aumento: 5 },
  { nome: 'Serra Azul Seguros', aumento: 9 },
  { nome: 'Seguradora Vale Verde', aumento: 15, semPdf: true },
  { nome: 'Horizonte Seguros' },
  { nome: 'Seguradora Ponte Nova' },
];
// Depois do prazo: duas deram preço, uma não respondeu a tempo, uma recusou e
// de uma falta a senha no Agger.
const RESPOSTAS_DEPOIS_DO_PRAZO = [
  { nome: 'Seguradora Atlântica', aumento: 5 },
  { nome: 'Serra Azul Seguros', aumento: 9 },
  { nome: 'Horizonte Seguros' },
  { nome: 'Seguradora Ponte Nova', recusou: true },
  { nome: 'Seguradora Monte Claro', faltaSenha: true },
];
// Por que a seguradora não quis cotar, por tipo de seguro.
const RECUSAS = {
  auto: 'nao_aceita_este_carro',
  residencial: 'nao_aceita_este_imovel',
};
const RECUSA_DE_SEMPRE = 'nao_aceita_este_seguro';

const resposta = (seguro, item) => ({
  nome: item.nome,
  semPdf: Boolean(item.semPdf),
  variacao: item.aumento ?? null,
  valor: item.aumento ? comAumento(seguro.valor, item.aumento) : null,
  periodo: seguro.periodo,
  recusou: item.recusou ? (RECUSAS[seguro.tipo] ?? RECUSA_DE_SEMPRE) : null,
  faltaSenha: Boolean(item.faltaSenha),
});

export const respostasPara = seguro =>
  RESPOSTAS_DA_COTACAO.map(item => resposta(seguro, item));

export const propostaDeExemplo = seguro => ({
  seguradora: seguro.seguradora,
  valor: comAumento(seguro.valor, AUMENTO_DA_PROPOSTA_ANEXADA),
  variacao: AUMENTO_DA_PROPOSTA_ANEXADA,
  periodo: seguro.periodo,
  mesmaCobertura: true,
});

// ---- quando cada caso vale ---------------------------------------------------

// A cotação ainda não deu em nada: sem proposta e sem cotação em andamento.
const semProposta = ({ renovacao }) =>
  !renovacao.proposta && !renovacao.cotando;
// A proposta está pronta e ninguém enviou.
const esperandoEnvio = ({ renovacao }) =>
  Boolean(renovacao.proposta) && !renovacao.proposta.enviadaEm;
const comProposta = ({ renovacao }) => Boolean(renovacao.proposta);

const naRenovacao = mudar => seguro => ({
  renovacao: { ...seguro.renovacao, ...mudar(seguro) },
});
const naProposta = mudar => (seguro, agora) => ({
  renovacao: {
    ...seguro.renovacao,
    proposta: { ...seguro.renovacao.proposta, ...mudar(seguro, agora) },
  },
});
const antesDaProposta = mudar => ({
  vale: semProposta,
  mudar: naRenovacao(mudar),
});

// Seguro por assinatura: o valor de hoje e o preço novo são por mês.
const porAssinatura = seguro => {
  const mensal = {
    ...seguro,
    valor: porMes(seguro.valor),
    periodo: PERIODOS.MES,
  };
  return {
    valor: mensal.valor,
    periodo: mensal.periodo,
    renovacao: { ...seguro.renovacao, proposta: propostaDeExemplo(mensal) },
  };
};

const CASOS = {
  cotacao_parcial: antesDaProposta(seguro => ({
    respostas: respostasPara(seguro),
  })),
  cotacao_parcial_prazo: antesDaProposta(seguro => ({
    passouOPrazo: true,
    respostas: RESPOSTAS_DEPOIS_DO_PRAZO.map(item => resposta(seguro, item)),
  })),
  cotacao_sem_pdf: antesDaProposta(seguro => ({
    proposta: { ...propostaDeExemplo(seguro), semPdf: true },
  })),
  cotacao_por_mes: { vale: semProposta, mudar: porAssinatura },
  cotacao_agger_fora: antesDaProposta(() => ({ parou: 'agger_fora' })),
  cotacao_demorou: antesDaProposta(() => ({ parou: 'demorou' })),
  cotacao_falhou: antesDaProposta(() => ({ parou: 'falhou' })),
  // Conta sem agente: ninguém perguntou os dados que faltam.
  cotacao_sem_agente: antesDaProposta(() => ({ perguntou: null })),
  // Faltam os dados do tipo do seguro (auto ou residencial) e ninguém perguntou.
  cotacao_faltam_dados: antesDaProposta(seguro => ({
    faltou: DADOS_PARA_COTAR[seguro.tipo] ?? [],
    perguntou: null,
  })),
  cotacao_falta_um_dado: antesDaProposta(() => ({
    faltou: ['nascimento'],
    perguntou: null,
  })),
  // O preço mudou, mas a cobertura não é a mesma do ano passado.
  cobertura_diferente: {
    vale: comProposta,
    mudar: naProposta(() => ({ mesmaCobertura: false })),
  },
  pessoa_bloqueada: {
    vale: esperandoEnvio,
    mudar: seguro => ({ pessoa: { ...seguro.pessoa, blocked: true } }),
  },
  // A pessoa não escreve há mais de um dia.
  fora_da_janela: {
    vale: esperandoEnvio,
    mudar: () => ({ foraDaJanela: true }),
  },
  // A proposta ia sair sozinha e o WhatsApp não deixou.
  proposta_nao_saiu: {
    vale: esperandoEnvio,
    mudar: naProposta((_seguro, agora) => ({
      naoSaiuEm: emSegundos(agora - NAO_SAIU_HA_HORAS * HORA_EM_MS),
    })),
  },
};

export const comOCaso = (seguro, caso, agora = Date.now()) => {
  const doCaso = CASOS[caso];
  if (!doCaso || !seguro?.renovacao || seguro.renovacao.desfecho) return seguro;
  const mexida = Boolean(escritaDe(seguro.id).campos.renovacao);
  if (mexida || !doCaso.vale(seguro)) return seguro;
  return { ...seguro, ...doCaso.mudar(seguro, agora) };
};
