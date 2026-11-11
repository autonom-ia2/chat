// #2897 — a história fictícia de cada seguro: o que aconteceu, quando e quem
// fez, do mais novo para o mais velho. O texto de cada passo é do catálogo
// (pelo `tipo`); aqui ficam só os fatos. O que a pessoa "disse" é inventado.
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
      acao: 'ver_proposta',
    }),
    passo('proposta_pronta', diaEHora(agora, 6, 9, 40), {
      quem: ROBO,
      valores: {
        seguradora: seguro.seguradora,
        valor: proposta.valor,
        variacao: proposta.variacao,
      },
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
    {
      quem: ROBO,
      valores: {
        seguradora: proposta.seguradora ?? seguro.seguradora,
        valor: proposta.valor,
        variacao: proposta.variacao,
      },
    }
  );
  if (!proposta.enviadaEm || proposta.enviadaPor?.papel) return [pronta];
  const envio = proposta.enviadaSozinha
    ? passo('proposta_enviada_sozinha', proposta.enviadaEm)
    : passo('proposta_enviada', proposta.enviadaEm, {
        quem: { nome: proposta.enviadaPor },
        acao: 'ver_proposta',
      });
  return [envio, pronta];
};

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
export const historiaDaDemo = (seguro, feitos = [], agora = Date.now()) =>
  [
    ...doQueFoiFeito(feitos).reverse(),
    ...daSituacao(seguro, agora, feitos),
    chegada(seguro),
  ]
    .map((item, ordem) => ({ ...item, ordem }))
    .sort((a, b) => b.quando - a.quando || a.ordem - b.ordem)
    .map(({ ordem, ...item }, indice) => ({ ...item, id: indice + 1 }));
