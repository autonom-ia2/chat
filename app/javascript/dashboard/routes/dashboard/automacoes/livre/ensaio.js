// #2498 — As linhas do ensaio a partir do que a API devolve: um nó por passo
// ({ id, tipo, faria, dados, ramos }). Quem abre caminhos (o "esperar até" que
// ainda não vale e o "decidir" da IA) põe um rótulo por caminho e os passos
// dele um nível adentro. A frase de cada passo é a do editor (`fraseDe`).
const E = 'AUTOMACAO_LIVRE.ENSAIO';

const AVISO = {
  mensagens_desligadas: 'NAO_SAIRIA',
  faltou_valor: 'FALTOU_VALOR',
  texto_vazio: 'TEXTO_VAZIO',
};

// #2500 F7 — os passos de IA no ensaio: o que a IA faria e para onde iria,
// sem chamar a IA (o servidor manda só o que a receita diz).
const F = `${E}.FARIA`;
const LUGAR = { conversa: 'CONVERSA', contato: 'CONTATO', empresa: 'EMPRESA' };
const ondeGrava = (campo, t) =>
  t(`${F}.ONDE.${LUGAR[(campo.destino || '').split('.')[0]]}`, {
    campo: campo.chave,
  });
const FARIA_DA_IA = {
  ia_extrair: (dados, t) =>
    t(`${F}.IA_EXTRAIR`, {
      lista: (dados.campos || []).map(campo => ondeGrava(campo, t)).join('; '),
    }),
  ia_escrever: (dados, t) =>
    t(
      `${F}.IA_ESCREVER_${dados.destino === 'mensagem' ? 'MENSAGEM' : 'SUGESTAO'}`
    ),
  ia_resumir: (dados, t) =>
    t(`${F}.IA_RESUMIR_${dados.destino === 'avisar' ? 'AVISAR' : 'NOTA'}`),
};

const rotuloDoCaminho = (no, ramo, t) => {
  if (no.tipo === 'esperar_ate')
    return t(`${E}.${ramo.chave === 'chegou' ? 'SE_CHEGAR' : 'SE_VENCER'}`);
  if (ramo.chave === 'nenhum') return t(`${E}.SE_NENHUM`);
  return t(`${E}.SE_CAMINHO`, { nome: ramo.nome || ramo.chave });
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
  if (AVISO[no.faria]) return { ...base, aviso: t(`${E}.${AVISO[no.faria]}`) };
  if (FARIA_DA_IA[no.faria])
    return { ...base, destaque: FARIA_DA_IA[no.faria](no.dados || {}, t) };
  if (no.dados?.texto) return { ...base, balao: no.dados.texto };
  return base;
};

export const linhasDoEnsaio = (nos, fraseDe, t, nivel = 0) =>
  (nos || []).flatMap(no => [
    linhaDoNo(no, fraseDe, t, nivel),
    ...(no.ramos || []).flatMap(ramo => [
      { nivel: nivel + 1, caminho: true, texto: rotuloDoCaminho(no, ramo, t) },
      ...linhasDoEnsaio(ramo.passos, fraseDe, t, nivel + 2),
    ]),
  ]);
