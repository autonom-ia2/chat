// #2897 — a história fictícia de cada seguro: o que aconteceu, quando e quem
// fez, do mais novo para o mais velho. O texto de cada passo é do catálogo
// (pelo `tipo`); aqui ficam só os fatos. O que a pessoa "disse" é inventado.
import { DIAS_DAS_MENSAGENS } from '../carteira/ajustesDaRenovacao';
import { DIA_EM_MS } from '../fonte/grupos';

const ROBO = { papel: 'robo' };
const RESPOSTA_DE_EXEMPLO = 'Vou ver com a minha esposa e te falo.';
const CARD_NASCE_HA_DIAS = 7;

// "há N dias, às hh:mm" em segundos.
const diaEHora = (agora, haDias, hora, minuto) => {
  const dia = new Date(agora - haDias * DIA_EM_MS);
  dia.setHours(hora, minuto, 0, 0);
  return Math.floor(dia.getTime() / 1000);
};

const passo = (tipo, quando, extras = {}) => ({
  tipo,
  quando,
  quem: null,
  valores: {},
  acao: null,
  mudancas: null,
  ...extras,
});

const primeiroNome = seguro => seguro.pessoa.name.split(' ')[0];

// O que a história diz da proposta: de quem é, quanto, por ano ou por mês, e
// (só com a mesma cobertura) quanto mudou.
const daPropostaEmValores = (seguro, proposta) => ({
  seguradora: proposta.seguradora ?? seguro.seguradora,
  valor: proposta.valor,
  periodo: proposta.periodo,
  variacao: proposta.variacao,
  mesmaCobertura: proposta.mesmaCobertura,
});
// O link do que saiu: a proposta oficial ou o resumo da cotação.
const verOQueSaiu = proposta =>
  proposta.oficial ? 'ver_proposta' : 'ver_resumo';

const chegada = seguro =>
  seguro.origem.tipo === 'planilha'
    ? passo('chegou_planilha', seguro.origem.em, {
        valores: { arquivo: seguro.origem.arquivo },
      })
    : passo('chegou_agger', seguro.origem.em);

// O seguro 1 conta a renovação inteira, passo a passo (BLOCO-B, Tela 15).
const daRenovacaoCompleta = (seguro, agora) => {
  const nome = primeiroNome(seguro);
  const { proposta, cuida } = seguro.renovacao;
  return [
    passo('cliente_respondeu', diaEHora(agora, 2, 14, 20), {
      valores: { nome, texto: RESPOSTA_DE_EXEMPLO },
    }),
    passo('proposta_enviada', diaEHora(agora, 5, 10, 5), {
      quem: { nome: cuida },
      acao: verOQueSaiu(proposta),
    }),
    passo('proposta_pronta', diaEHora(agora, 6, 9, 40), {
      quem: ROBO,
      valores: daPropostaEmValores(seguro, proposta),
    }),
    passo('respondeu_algo_mudou', diaEHora(agora, 6, 9, 2), {
      valores: { nome },
    }),
    passo('card_nasceu', diaEHora(agora, CARD_NASCE_HA_DIAS, 7, 0), {
      valores: { funil: seguro.renovacao.funil, etapa: 'A vencer' },
    }),
  ];
};

const SEGURO_DA_RENOVACAO_COMPLETA = 1;
const MINUTOS_ATE_ENVIAR = 25 * 60;
const PRONTA_HA_DIAS = 1;

// A proposta que ia sair sozinha e não saiu: fica dita até alguém enviar.
const propostaQueNaoSaiu = seguro => {
  const { proposta } = seguro.renovacao ?? {};
  return proposta && !proposta.enviadaEm && proposta.naoSaiuEm
    ? [passo('proposta_nao_saiu', proposta.naoSaiuEm)]
    : [];
};

// A proposta de uma renovação qualquer: quando ficou pronta e, se já saiu, se
// alguém enviou ou se saiu sozinha. O que a pessoa enviou agora já está nos
// "feitos" (enviadaPor com papel), e não se repete aqui.
const daProposta = (seguro, agora) => {
  const { proposta } = seguro.renovacao ?? {};
  if (!proposta) return [];
  const pronta = passo(
    'proposta_pronta',
    proposta.enviadaEm
      ? proposta.enviadaEm - MINUTOS_ATE_ENVIAR
      : diaEHora(agora, PRONTA_HA_DIAS, 9, 40),
    { quem: ROBO, valores: daPropostaEmValores(seguro, proposta) }
  );
  const naoSaiu = propostaQueNaoSaiu(seguro);
  if (naoSaiu.length) return [...naoSaiu, pronta];
  if (!proposta.enviadaEm || proposta.enviadaPor?.papel) return [pronta];
  const envio = proposta.enviadaSozinha
    ? passo('proposta_enviada_sozinha', proposta.enviadaEm)
    : passo('proposta_enviada', proposta.enviadaEm, {
        quem: { nome: proposta.enviadaPor },
        acao: verOQueSaiu(proposta),
      });
  return [envio, pronta];
};

// ---- o que ia sair sozinho e não saiu (`?caso=`) ------------------------------

const NAO_SAIU_HA_DIAS = 1;
// O aviso mais recente que já devia ter saído: aos 30, 15 ou 7 dias do fim.
const diasDoAviso = (seguro, agora) => {
  const faltam = (seguro.termina * 1000 - agora) / DIA_EM_MS;
  const jaDeviam = DIAS_DAS_MENSAGENS.filter(dias => dias >= faltam);
  return jaDeviam.length ? Math.min(...jaDeviam) : DIAS_DAS_MENSAGENS[0];
};
const NAO_SAIRAM = {
  aviso_nao_saiu: (seguro, agora) =>
    seguro.renovacao
      ? passo('aviso_nao_saiu', diaEHora(agora, NAO_SAIU_HA_DIAS, 9, 0), {
          valores: { dias: diasDoAviso(seguro, agora) },
        })
      : null,
  algo_mudou_nao_saiu: (seguro, agora) =>
    seguro.renovacao
      ? passo('algo_mudou_nao_saiu', diaEHora(agora, NAO_SAIU_HA_DIAS, 9, 2))
      : null,
  palavras_nao_saiu: (seguro, agora) =>
    seguro.palavras && !seguro.palavras.enviadoEm
      ? passo('palavras_nao_saiu', diaEHora(agora, NAO_SAIU_HA_DIAS, 10, 30))
      : null,
};
const doCaso = (seguro, agora, caso) =>
  [NAO_SAIRAM[caso]?.(seguro, agora)].filter(Boolean);

// O que o seguro traz em `naoSaiu` (carteira/oQueNaoSaiu.js): os mesmos fatos
// que a história conta, para a gaveta dizer no topo o que não saiu.
export const naoSaiuNaDemo = (seguro, agora = Date.now(), caso = null) =>
  [...doCaso(seguro, agora, caso), ...propostaQueNaoSaiu(seguro)].map(
    ({ tipo, quando, valores }) => ({
      tipo,
      em: quando,
      dias: valores.dias ?? null,
    })
  );

const daSituacao = (seguro, agora, feitos) => {
  const jaFeito = tipo => feitos.some(item => item.tipo === tipo);
  if (
    seguro.id === SEGURO_DA_RENOVACAO_COMPLETA &&
    seguro.renovacao?.proposta
  ) {
    return daRenovacaoCompleta(seguro, agora);
  }
  return [
    ...daProposta(seguro, agora),
    seguro.renovacao
      ? passo('card_nasceu', diaEHora(agora, CARD_NASCE_HA_DIAS, 7, 0), {
          valores: { funil: seguro.renovacao.funil, etapa: 'A vencer' },
        })
      : null,
    seguro.endosso
      ? passo('endosso', seguro.endosso.em, {
          mudancas: [
            {
              campo: seguro.endosso.campo,
              antes: seguro.endosso.antes,
              depois: seguro.endosso.depois,
            },
          ],
        })
      : null,
    // O que foi marcado agora no card já está nos "feitos".
    seguro.renovadoEm && !jaFeito('renovou')
      ? passo('renovou', seguro.renovadoEm)
      : null,
    seguro.motivo && !seguro.renovacao
      ? passo('nao_renovou', seguro.termina, {
          valores: { motivo: seguro.motivo },
        })
      : null,
  ].filter(Boolean);
};

const doQueFoiFeito = feitos =>
  feitos.map(({ tipo, quando, valores }) =>
    passo(tipo, quando, { quem: { papel: 'voce' }, valores })
  );

// Na ordem da tela: o mais novo primeiro; no empate, o que foi feito por último.
export const historiaDaDemo = (
  seguro,
  feitos = [],
  agora = Date.now(),
  caso = null
) =>
  [
    ...doQueFoiFeito(feitos).reverse(),
    ...doCaso(seguro, agora, caso),
    ...daSituacao(seguro, agora, feitos),
    chegada(seguro),
  ]
    .map((item, ordem) => ({ ...item, ordem }))
    .sort((a, b) => b.quando - a.quando || a.ordem - b.ordem)
    .map(({ ordem, ...item }, indice) => ({ ...item, id: indice + 1 }));
