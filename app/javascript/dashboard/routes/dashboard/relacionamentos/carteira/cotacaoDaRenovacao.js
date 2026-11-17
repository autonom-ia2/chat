// #2901 (E8) — a cotação da renovação, em regras puras: as escolhas de
// "Ajustar renovações" (quem cota, como a proposta sai, quem responde o
// cliente e por qual WhatsApp) e em que pé está a cotação de cada seguro, em
// palavras de gente. Quem desenha traduz: daqui saem só os nomes das frases e
// o que elas precisam, nunca o código do servidor.
//
// O servidor só manda a parte da cotação quando a chave dela está ligada na
// conta (`cotacaoLiberada`). Sem a chave, nada daqui aparece e a tela é a da
// E5.
export const QUEM_COTA = { NINGUEM: 'ninguem', ROBO: 'robo', LIA: 'lia' };
export const QUEM_ENVIA = { PESSOA: 'pessoa', SOZINHO: 'sozinho' };
export const QUEM_RESPONDE = { EQUIPE: 'equipe', LIA: 'lia' };

// As escolhas da cotação nos ajustes, como o servidor as manda e as recebe.
export const ESCOLHAS_DA_COTACAO = [
  'quemCota',
  'quemEnvia',
  'quemResponde',
  'caixaId',
];

// O servidor mandou as escolhas da cotação (a chave está ligada na conta).
export const temEscolhasDaCotacao = ajustes =>
  Object.values(QUEM_COTA).includes(ajustes?.quemCota);

// Só as escolhas da cotação, quando vieram ({} sem elas).
export const escolhasDaCotacao = ajustes =>
  temEscolhasDaCotacao(ajustes)
    ? {
        quemCota: ajustes.quemCota,
        quemEnvia: ajustes.quemEnvia,
        quemResponde: ajustes.quemResponde,
        caixaId: ajustes.caixaId ?? null,
      }
    : {};

// O robô só cota na conta que tem o Agente de Cotação e um WhatsApp oficial
// para mandar as mensagens (o "Algo mudou?" e a proposta saem por ele): sem um
// dos dois, só "Ninguém" aparece, com a frase do porquê ('' = o robô pode).
export const SO_NINGUEM = { SEM_AGENTE: 'SEM_AGENTE', SEM_CAIXA: 'SEM_CAIXA' };
export const porQueSoNinguem = conta => {
  if (!conta?.cotaSozinha) return SO_NINGUEM.SEM_AGENTE;
  return conta?.caixas?.length ? '' : SO_NINGUEM.SEM_CAIXA;
};
export const roboPodeCotar = conta => !porQueSoNinguem(conta);

// O robô cota: as outras três perguntas passam a valer.
export const roboCota = ajustes =>
  temEscolhasDaCotacao(ajustes) && ajustes.quemCota !== QUEM_COTA.NINGUEM;

// Quem responde o cliente depois é o agente (pela escolha de quem cota ou de
// quem responde).
export const agenteResponde = ajustes =>
  ajustes?.quemCota === QUEM_COTA.LIA ||
  ajustes?.quemResponde === QUEM_RESPONDE.LIA;

export const caixaEscolhida = (caixas = [], caixaId = null) =>
  caixas.find(caixa => caixa.id === caixaId) ?? null;

// O agente vai responder, mas não está ligado no WhatsApp escolhido: a
// resposta do cliente ficaria sem ninguém. A tela avisa antes de salvar.
export const agenteForaDaCaixa = (ajustes, caixas = []) => {
  if (!roboCota(ajustes) || !agenteResponde(ajustes)) return false;
  const caixa = caixaEscolhida(caixas, ajustes.caixaId);
  return Boolean(caixa) && !caixa.liaLigada;
};

// O agente vai responder, mas o WhatsApp escolhido entrega toda conversa nova a
// alguém da equipe, e o agente não responde conversa que está com alguém. A
// tela avisa antes de salvar; o servidor recusa (`caixa_distribui`).
export const caixaDistribui = (ajustes, caixas = []) => {
  if (!roboCota(ajustes) || !agenteResponde(ajustes)) return false;
  return Boolean(caixaEscolhida(caixas, ajustes.caixaId)?.distribui);
};

// O robô cota e falta escolher por qual WhatsApp as mensagens saem.
export const faltaCaixa = ajustes => roboCota(ajustes) && !ajustes.caixaId;

// ---- em que pé está a cotação de um seguro ---------------------------------

export const ETAPAS = {
  PEDIDA: 'cotacao_pedida',
  PERGUNTA_NAO_SAIU: 'algo_mudou_nao_saiu',
  RESPONDEU: 'respondeu_algo_mudou',
  CLIENTE_CONTOU: 'cliente_respondeu',
  COTANDO: 'proposta_pedida',
  NAO_SAIU: 'proposta_nao_saiu',
  PRONTA: 'proposta_pronta',
  ENVIADA: 'proposta_enviada',
  ENVIADA_SOZINHA: 'proposta_enviada_sozinha',
};
export const RESPOSTAS = { NADA_MUDOU: 'nada_mudou', MUDOU: 'mudou' };

// Os motivos que têm frase. O servidor pode ganhar um motivo antes da tela: o
// que não está aqui vira a frase de sempre, nunca o código.
const MOTIVOS_DA_COTACAO = [
  'conferencia_caiu',
  'sem_conexao',
  'sem_agente',
  'cotacao_falhou',
  'sem_preco',
  'sem_pdf',
  'envio',
];
const MOTIVOS_DO_ENVIO = [
  'contato_recusou',
  'sem_caixa',
  'sem_modelo',
  'sem_telefone',
  'campo_vazio',
  'sem_card',
];
const FALTOU_DADO = 'faltou_dado';

// Os campos que faltaram e têm nome no catálogo (COTACAO.CAMPOS), pelo nome
// que o servidor manda ("insured.name"). O nome do catálogo troca o ponto por
// "_" e vai em maiúsculas.
const CAMPOS_COM_NOME = [
  'produto',
  'quotation.previousInsurerCode',
  'quotation.previousPolicyNumber',
  'quotation.previousPolicyEndDate',
  'quotation.bonusClass',
  'insured.name',
  'insured.document',
  'insured.birthDate',
  'insured.gender',
  'address.zipCode',
  'vehicle.plate',
  'renovacao.seguradoraAnterior',
  'renovacao.numeroApolice',
  'renovacao.fimVigencia',
  'renovacao.bonus',
  'segurado.cpfCnpj',
  'segurado.nome',
  'segurado.cep',
];
// #3043 (E8.1) — os dados que a apólice traz escrita: quando um deles falta, a
// frase ensina o caminho (anexar o PDF da apólice ou corrigir o seguro à mão).
const DA_APOLICE = [
  'quotation.bonusClass',
  'insured.birthDate',
  'insured.gender',
  'address.zipCode',
  'vehicle.plate',
  'renovacao.bonus',
  'segurado.cep',
];
export const chaveDoCampo = campo => campo.split('.').join('_').toUpperCase();

// Os campos que faltaram, em chaves do catálogo, sem repetir (dois nomes do
// servidor podem ter o mesmo nome em português). `outros`: faltou também algo
// que a tela não sabe nomear. `daApolice`: faltou algo que a apólice traz.
export const camposQueFaltam = (faltam = []) => {
  const conhecidos = faltam.filter(campo => CAMPOS_COM_NOME.includes(campo));
  return {
    campos: [...new Set(conhecidos.map(chaveDoCampo))],
    outros: conhecidos.length < faltam.length,
    daApolice: faltam.some(campo => DA_APOLICE.includes(campo)),
  };
};

export const SITUACOES_DA_COTACAO = {
  PERGUNTOU: 'PERGUNTOU',
  PERGUNTA_NAO_SAIU: 'PERGUNTA_NAO_SAIU',
  NADA_MUDOU: 'NADA_MUDOU',
  MUDOU: 'MUDOU',
  CLIENTE_CONTOU: 'CLIENTE_CONTOU',
  COTANDO: 'COTANDO',
  FALTAM: 'FALTAM',
  NAO_SAIU: 'NAO_SAIU',
  NAO_SAIU_SEM_MOTIVO: 'NAO_SAIU_SEM_MOTIVO',
  PRONTA: 'PRONTA',
  ENVIADA: 'ENVIADA',
  ENVIADA_SOZINHA: 'ENVIADA_SOZINHA',
  ANDANDO: 'ANDANDO',
  INCERTA: 'INCERTA',
};
const S = SITUACOES_DA_COTACAO;

const daPergunta = ({ motivo }) =>
  MOTIVOS_DO_ENVIO.includes(motivo)
    ? { id: S.PERGUNTA_NAO_SAIU, motivo }
    : { id: S.PERGUNTA_NAO_SAIU, motivo: null };

// Faltou dado: a frase diz quais, pelo nome; o que a tela não sabe nomear vira
// "outros dados do seguro". Sem a lista, só que não deu para cotar.
const doQueNaoSaiu = ({ motivo, faltam }) => {
  if (motivo === FALTOU_DADO) {
    return faltam?.length
      ? { id: S.FALTAM, ...camposQueFaltam(faltam) }
      : { id: S.NAO_SAIU_SEM_MOTIVO };
  }
  return MOTIVOS_DA_COTACAO.includes(motivo)
    ? { id: S.NAO_SAIU, motivo }
    : { id: S.NAO_SAIU_SEM_MOTIVO };
};

const PELA_ETAPA = {
  [ETAPAS.PEDIDA]: () => ({ id: S.PERGUNTOU }),
  [ETAPAS.PERGUNTA_NAO_SAIU]: daPergunta,
  [ETAPAS.RESPONDEU]: ({ resposta }) => ({
    id: resposta === RESPOSTAS.MUDOU ? S.MUDOU : S.NADA_MUDOU,
  }),
  [ETAPAS.CLIENTE_CONTOU]: () => ({ id: S.CLIENTE_CONTOU }),
  [ETAPAS.COTANDO]: () => ({ id: S.COTANDO }),
  [ETAPAS.NAO_SAIU]: doQueNaoSaiu,
  [ETAPAS.PRONTA]: ({ premioCentavos, seguradora }) => ({
    id: S.PRONTA,
    premioCentavos,
    seguradora,
  }),
  [ETAPAS.ENVIADA]: ({ enviadaEm }) => ({ id: S.ENVIADA, enviadaEm }),
  [ETAPAS.ENVIADA_SOZINHA]: ({ enviadaEm }) => ({
    id: S.ENVIADA_SOZINHA,
    enviadaEm,
  }),
};

// A frase principal da cotação de um seguro: `{ id, ...o que ela precisa }`,
// ou null quando o seguro não tem cotação. A etapa que a tela ainda não
// conhece diz só que a cotação está andando. A proposta que não se sabe se
// chegou (`incerta`) pede para conferir na conversa, qualquer que seja a etapa.
export const situacaoDaCotacao = cotacao => {
  if (!cotacao?.etapa) return null;
  if (cotacao.incerta) return { id: S.INCERTA };
  const daEtapa = PELA_ETAPA[cotacao.etapa];
  return daEtapa ? daEtapa(cotacao) : { id: S.ANDANDO };
};

// A proposta já tem preço e a frase principal não é a dela ("Proposta pronta:
// R$ X"): depois de enviada, o preço continua à vista numa linha embaixo.
export const mostraAProposta = cotacao =>
  Boolean(cotacao?.premioCentavos) && cotacao.etapa !== ETAPAS.PRONTA;

// A variação contra o ano passado: `{ id: SUBIU | CAIU | IGUAL, percentual }`,
// sempre positivo, ou null (sem valor do ano passado ou sem proposta, a linha
// não aparece).
export const VARIACOES = { SUBIU: 'SUBIU', CAIU: 'CAIU', IGUAL: 'IGUAL' };
export const variacaoDaCotacao = cotacao => {
  const variacao = cotacao?.variacaoPercentual;
  if (typeof variacao !== 'number' || Number.isNaN(variacao)) return null;
  if (variacao > 0) return { id: VARIACOES.SUBIU, percentual: variacao };
  if (variacao < 0) return { id: VARIACOES.CAIU, percentual: -variacao };
  return { id: VARIACOES.IGUAL, percentual: 0 };
};

// Estados em que alguém da equipe precisa olhar: o servidor já avisou no card,
// e a gaveta diz isso. A conferência que caiu não entra: ela tenta de novo
// sozinha, e a frase dela já diz isso.
const PEDEM_ALGUEM = [
  S.PERGUNTA_NAO_SAIU,
  S.MUDOU,
  S.CLIENTE_CONTOU,
  S.FALTAM,
  S.NAO_SAIU_SEM_MOTIVO,
];
export const equipeFoiAvisada = situacao =>
  PEDEM_ALGUEM.includes(situacao?.id) ||
  (situacao?.id === S.NAO_SAIU && situacao.motivo !== 'conferencia_caiu');

// A proposta que não se sabe se chegou: o botão diz "Enviar de novo".
export const enviaDeNovo = cotacao => Boolean(cotacao?.incerta);

// O botão "Enviar proposta": só com a proposta pronta e ainda não enviada, para
// quem pode alterar a pessoa e enxerga o card da renovação no funil (o
// servidor pede os dois), e nunca no seguro cancelado.
export const podeEnviarProposta = (seguro, podeEditar) =>
  Boolean(
    podeEditar &&
      seguro?.cotacao?.podeEnviar &&
      seguro.renovacao?.cardId &&
      !seguro.canceladoEm
  );

export const CENTAVOS_POR_REAL = 100;
export const emReais = centavos => centavos / CENTAVOS_POR_REAL;
