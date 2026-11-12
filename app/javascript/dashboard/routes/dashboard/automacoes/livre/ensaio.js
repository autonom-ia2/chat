// #2498 — As linhas do ensaio a partir do que a API devolve: um nó por passo
// ({ id, tipo, faria, dados, ramos }). Quem abre caminhos (o "esperar até" que
// ainda não vale e o "decidir" da IA) põe um rótulo por caminho e os passos
// dele um nível adentro. A frase de cada passo é a do editor (`fraseDe`).
import { formatAttributeDate } from 'dashboard/helper/attributeDate';
import {
  linhaDoEnsaioComMotor,
  linhaDoEnsaioNovo,
  rotuloDoGalhoFixo,
} from './passosNovos/frasesDosNovos';
import { temMotor } from './passosNovos/passosNovos';

const E = 'AUTOMACAO_LIVRE.ENSAIO';

const AVISO = {
  mensagens_desligadas: 'NAO_SAIRIA',
  faltou_valor: 'FALTOU_VALOR',
  // G12/G44: o link da agenda vazio, e quem pede sem ver o agendamento.
  faltou_link_da_agenda: 'FALTOU_LINK_DA_AGENDA',
  sem_acesso_agenda: 'SEM_ACESSO_AGENDA',
  texto_vazio: 'TEXTO_VAZIO',
  // G2: o e-mail que não sairia para o contato desta conversa.
  contato_sem_email: 'CONTATO_SEM_EMAIL',
  contato_nao_recebe: 'CONTATO_NAO_RECEBE',
  // Decisão 5 (#2414): o bloqueado não recebe nada da automação.
  contato_bloqueado: 'CONTATO_BLOQUEADO',
  email_bloqueado: 'EMAIL_BLOQUEADO',
  caixa_de_email_indisponivel: 'CAIXA_DE_EMAIL_INDISPONIVEL',
  // #2609: a mensagem pula, como no motor.
  canal_sem_resposta: 'CANAL_SEM_RESPOSTA',
  retorno_sem_responsavel: 'RETORNO_SEM_RESPONSAVEL',
  sem_responsavel: 'SEM_RESPONSAVEL',
  caixa_sem_ninguem: 'CAIXA_SEM_NINGUEM',
};

// #2552: por que o aviso iria para quem atende a caixa.
const RESERVA = {
  sem_responsavel: 'IRIA_PARA_CAIXA',
  responsavel_fora: 'IRIA_PARA_CAIXA_FORA',
};

// #2414 G16 — a ação com valor calculado: o que gravaria agora (a data com o
// "hoje" de agora), ou por que pularia, como o motor.
const AVISO_DA_ACAO = {
  faltou_valor: 'ACAO_FALTOU_VALOR',
  data_invalida: 'DATA_INVALIDA',
  valor_fora_do_formato: 'VALOR_FORA_DO_FORMATO',
};
const gravaria = (calculados, t) =>
  t(`${E}.FARIA.GRAVARIA`, {
    lista: calculados
      .map(
        item =>
          `${item.campo}: ${formatAttributeDate(item.valor) || item.valor}`
      )
      .join('; '),
  });

// #2500 F7 — os passos de IA no ensaio: o que a IA faria e para onde iria,
// sem chamar a IA (o servidor manda só o que a receita diz).
const F = `${E}.FARIA`;
const LUGAR = { conversa: 'CONVERSA', contato: 'CONTATO', empresa: 'EMPRESA' };
// Lugar que este painel não conhece (ou destino vazio): só o campo, nunca a
// chave crua do i18n.
const ondeGrava = (campo, t) => {
  const lugar = LUGAR[(campo.destino || '').split('.')[0]];
  return lugar ? t(`${F}.ONDE.${lugar}`, { campo: campo.chave }) : campo.chave;
};
const FARIA_DA_IA = {
  ia_extrair: (dados, t) =>
    t(`${F}.IA_EXTRAIR`, {
      lista: (dados.campos || []).map(campo => ondeGrava(campo, t)).join('; '),
    }),
  ia_escrever: (dados, t) =>
    t(`${F}.IA_ESCREVER_${(dados.destino || 'sugestao').toUpperCase()}`),
  ia_resumir: (dados, t) =>
    t(`${F}.IA_RESUMIR_${dados.destino === 'avisar' ? 'AVISAR' : 'NOTA'}`),
  // G24: um card por item da lista, até o máximo do passo.
  ia_para_cada: (dados, t) =>
    t(`${F}.IA_PARA_CADA`, { maximo: dados.maximo ?? '' }),
};

// #2414 G20 — o passo de IA que lê os anexos: quantos desta conversa a IA
// leria, ou por que não seria chamada (como o motor).
const ANEXOS = 'AUTOMACAO_LIVRE.IA.ANEXOS';
const comAnexos = (linha, no, t) => {
  const { anexos, anexos_motivo: motivo } = no.dados || {};
  if (motivo)
    return { ...linha, aviso: t(`${ANEXOS}.${motivo.toUpperCase()}`) };
  if (anexos === undefined) return linha;
  const frase = t(`${ANEXOS}.LERIA`, { n: anexos }, anexos);
  return {
    ...linha,
    destaque: [linha.destaque, frase].filter(Boolean).join(' '),
  };
};

// G63: o galho "a cada mensagem do cliente" acaba com a marca `volta`.
const ROTULO_DA_ESPERA = {
  chegou: 'SE_CHEGAR',
  se_vencer: 'SE_VENCER',
  a_cada_mensagem: 'A_CADA_MENSAGEM',
};

const rotuloDoCaminho = (no, ramo, t) => {
  if (no.tipo === 'esperar_ate')
    return t(`${E}.${ROTULO_DA_ESPERA[ramo.chave] || 'SE_VENCER'}`);
  // G31: o caminho que decide de novo espera a próxima resposta.
  const deNovo = ramo.de_novo ? '_DE_NOVO' : '';
  if (ramo.chave === 'nenhum') return t(`${E}.SE_NENHUM${deNovo}`);
  // Protótipo #2931–#2936: o galho fixo do passo novo diz o próprio nome; os
  // galhos dos três com motor (#2932–#2934) também.
  if (ramo.fixo || temMotor(no)) return rotuloDoGalhoFixo(ramo.chave, t);
  return t(`${E}.SE_CAMINHO${deNovo}`, { nome: ramo.nome || ramo.chave });
};

// `fraseDe(id, no)`: o nó vai junto para o passo de dentro de um bloco (#2933,
// `no.bloco`), cujo id é da receita do bloco. `passoDe(no)`: o passo do nó,
// para a busca do ensaio (#2934).
const linhaDoNo = (no, fraseDe, t, nivel, passoDe) => {
  const base = { nivel, tipo: no.tipo, texto: fraseDe(no.id, no) };
  // Protótipo #2931–#2936: o passo novo diz o que faria (adaptadorFalso).
  if (no.faria === 'passo_novo')
    return { ...base, ...linhaDoEnsaioNovo(no.dados.passo, t) };
  if (temMotor(no))
    return { ...base, ...linhaDoEnsaioComMotor(no, t, passoDe(no)) };
  if (no.faria === 'corte') return { nivel, texto: t(`${E}.CORTE`) };
  if (no.faria === 'se')
    return {
      ...base,
      destaque: t(
        `${E}.${no.dados.ramo === 'entao' ? 'HOJE_SIM' : 'HOJE_NAO'}`
      ),
    };
  if (no.faria === 'esperar_ate_ja_vale')
    return { ...base, destaque: t(`${E}.JA_VALE`) };
  if (no.tipo === 'acao' && AVISO_DA_ACAO[no.faria])
    return { ...base, aviso: t(`${E}.${AVISO_DA_ACAO[no.faria]}`) };
  if (AVISO[no.faria]) return { ...base, aviso: t(`${E}.${AVISO[no.faria]}`) };
  // #2604: quem liga a automação não pode escrever nesta conversa ou caixa, ou
  // não pode mais gerenciar automações (saiu da conta, perdeu a permissão): o
  // motor pausaria a automação, e o caminho acaba aqui.
  if (no.faria === 'pausaria') {
    const chave =
      no.dados.motivo === 'quem_ligou_sem_acesso'
        ? 'PAUSARIA'
        : 'PAUSARIA_QUEM_LIGA';
    return { ...base, aviso: t(`${E}.${chave}`, { nome: no.dados.quem }) };
  }
  // #2609: a janela fechada sem modelo que saia no lugar: a execução pararia
  // aqui, com o motivo do motor, e o caminho acaba.
  if (no.faria === 'pararia')
    return {
      ...base,
      aviso: t(`${E}.PARARIA.${no.dados.motivo.toUpperCase()}`),
    };
  // G15: para quem passaria; se não passaria, o porquê, com o nome da agente.
  if (no.tipo === 'ia_assumir')
    return no.faria === 'ia_assumir'
      ? { ...base, destaque: t(`${E}.IA_ASSUMIR`, { agente: no.dados.agente }) }
      : {
          ...base,
          aviso: t(`${E}.NAO_PASSARIA.${no.faria.toUpperCase()}`, {
            agente: no.dados?.agente,
          }),
        };
  // #2502: entre quem seria o rodízio (quem está online só se sabe na hora);
  // se não passaria, o porquê.
  if (no.tipo === 'rodizio')
    return no.faria === 'rodizio'
      ? {
          ...base,
          destaque: no.dados?.time
            ? t(`${E}.RODIZIO_TIME`, { time: no.dados.time })
            : t(`${E}.RODIZIO_CAIXA`),
        }
      : { ...base, aviso: t(`${E}.NAO_RODARIA.${no.faria.toUpperCase()}`) };
  // G2: a linha já com o assunto montado (como o balão da mensagem), por qual
  // caixa sairia e o texto no balão.
  if (no.faria === 'email')
    return {
      ...base,
      texto: t('AUTOMACAO_LIVRE.FRASES.EMAIL', { assunto: no.dados.assunto }),
      destaque: t(`${E}.EMAIL`, { caixa: no.dados.caixa }),
      balao: no.dados.texto,
    };
  if (no.dados?.calculados?.length)
    return { ...base, destaque: gravaria(no.dados.calculados, t) };
  // A reserva da caixa (#2552): no avisar e no resumo que sai pelo avisar.
  const reserva = RESERVA[no.dados?.reserva];
  const caixa = reserva ? t(`${E}.${reserva}`) : null;
  if (FARIA_DA_IA[no.faria]) {
    const faria = FARIA_DA_IA[no.faria](no.dados || {}, t);
    return { ...base, destaque: caixa ? `${faria} ${caixa}` : faria };
  }
  if (caixa) return { ...base, balao: no.dados.texto, destaque: caixa };
  // F4b: com modelo, a tela diz o que sai se a janela de 24 h estiver fechada;
  // o de propaganda (lote 5, #2681) avisa que custa mais.
  if (no.dados?.texto)
    return {
      ...base,
      balao: no.dados.texto,
      ...(no.dados.modelo && {
        destaque: no.dados.propaganda
          ? t(`${E}.MODELO_PROPAGANDA_FORA_DA_JANELA`, {
              modelo: no.dados.modelo,
            })
          : t(`${E}.MODELO_FORA_DA_JANELA`, { modelo: no.dados.modelo }),
      }),
    };
  return base;
};

export const linhasDoEnsaio = (
  nos,
  fraseDe,
  t,
  nivel = 0,
  passoDe = () => null
) =>
  (nos || []).flatMap(no => [
    comAnexos(linhaDoNo(no, fraseDe, t, nivel, passoDe), no, t),
    ...(no.ramos || []).flatMap(ramo => [
      { nivel: nivel + 1, caminho: true, texto: rotuloDoCaminho(no, ramo, t) },
      ...linhasDoEnsaio(ramo.passos, fraseDe, t, nivel + 2, passoDe),
      // G46: o caminho que volta a um "esperar até" acaba dizendo para onde.
      ...(ramo.volta
        ? [
            {
              nivel: nivel + 2,
              texto: t(`${E}.VOLTA`, { passo: fraseDe(ramo.volta) }),
            },
          ]
        : []),
    ]),
  ]);
