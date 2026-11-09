// #2498 — As linhas do ensaio a partir do que a API devolve: um nó por passo
// ({ id, tipo, faria, dados, ramos }). Quem abre caminhos (o "esperar até" que
// ainda não vale e o "decidir" da IA) põe um rótulo por caminho e os passos
// dele um nível adentro. A frase de cada passo é a do editor (`fraseDe`).
import { formatAttributeDate } from 'dashboard/helper/attributeDate';

const E = 'AUTOMACAO_LIVRE.ENSAIO';

const AVISO = {
  mensagens_desligadas: 'NAO_SAIRIA',
  faltou_valor: 'FALTOU_VALOR',
  texto_vazio: 'TEXTO_VAZIO',
  // G2: o e-mail que não sairia para o contato desta conversa.
  contato_sem_email: 'CONTATO_SEM_EMAIL',
  contato_nao_recebe: 'CONTATO_NAO_RECEBE',
  email_bloqueado: 'EMAIL_BLOQUEADO',
  caixa_de_email_indisponivel: 'CAIXA_DE_EMAIL_INDISPONIVEL',
  retorno_sem_responsavel: 'RETORNO_SEM_RESPONSAVEL',
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

const rotuloDoCaminho = (no, ramo, t) => {
  if (no.tipo === 'esperar_ate')
    return t(`${E}.${ramo.chave === 'chegou' ? 'SE_CHEGAR' : 'SE_VENCER'}`);
  // G31: o caminho que decide de novo espera a próxima resposta.
  const deNovo = ramo.de_novo ? '_DE_NOVO' : '';
  if (ramo.chave === 'nenhum') return t(`${E}.SE_NENHUM${deNovo}`);
  return t(`${E}.SE_CAMINHO${deNovo}`, { nome: ramo.nome || ramo.chave });
};

const linhaDoNo = (no, fraseDe, t, nivel) => {
  const base = { nivel, tipo: no.tipo, texto: fraseDe(no.id) };
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
  if (FARIA_DA_IA[no.faria])
    return { ...base, destaque: FARIA_DA_IA[no.faria](no.dados || {}, t) };
  // F4b: com modelo, a tela diz o que sai se a janela de 24 h estiver fechada.
  if (no.dados?.texto)
    return {
      ...base,
      balao: no.dados.texto,
      ...(no.dados.modelo && {
        destaque: t(`${E}.MODELO_FORA_DA_JANELA`, { modelo: no.dados.modelo }),
      }),
    };
  return base;
};

export const linhasDoEnsaio = (nos, fraseDe, t, nivel = 0) =>
  (nos || []).flatMap(no => [
    comAnexos(linhaDoNo(no, fraseDe, t, nivel), no, t),
    ...(no.ramos || []).flatMap(ramo => [
      { nivel: nivel + 1, caminho: true, texto: rotuloDoCaminho(no, ramo, t) },
      ...linhasDoEnsaio(ramo.passos, fraseDe, t, nivel + 2),
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
