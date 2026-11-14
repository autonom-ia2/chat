// #2897 — as recusas da carteira que têm nome. Quando o servidor recusa o que a
// tela pediu (422), a resposta traz só um código (`{ error: "<código>" }`), nunca
// o que a pessoa digitou. A fonte dá a essa falha o nome `RECUSADO` e guarda o
// código; a tela escolhe a frase do catálogo pelo código e, como ele, nunca
// repete o valor digitado.
export const RECUSADO = 'RECUSADO';
// O PDF passou do tamanho que a instalação aceita: a tela confere antes de
// enviar e o servidor responde o mesmo código.
export const ARQUIVO_GRANDE = 'arquivo_grande';

export const CODIGOS_DE_RECUSA = [
  'falta_numero',
  'falta_seguradora',
  'falta_termina',
  'termina_antes',
  'data_invalida',
  'valor_invalido',
  'tipo_desconhecido',
  'apolice_repetida',
  'ja_cancelado',
  'nao_cancelado',
  'arquivo_obrigatorio',
  'tipo',
  ARQUIVO_GRANDE,
  'sem_pdf',
  'pedido_invalido',
  // #2898 — os ajustes das renovações.
  'funil_desconhecido',
  'etapa_de_outro_funil',
  'dias_invalidos',
  'mensagens_invalidas',
  // #2898 — como a renovação termina ("Renovou", "Não renovou", "Desfazer").
  'sem_renovacao',
  'ja_tem_desfecho',
  'sem_desfecho',
  'motivo_desconhecido',
  'falta_texto',
  'texto_longo',
  // #2898 — a apólice nova do seguro que renovou.
  'anterior_desconhecida',
  'anterior_cancelada',
  'ja_tem_apolice_nova',
  'falta_tipo',
  'termina_antes_da_anterior',
  'apolice_de_outra_pessoa',
  'termo_ambiguo',
  // #2899 — a leitura de PDF: anexar e ver o que mudou, e trazer por PDFs.
  'leitura_desligada',
  'nao_e_apolice',
  'nao_deu_para_ler',
  'leitura_expirou',
  'leitura_nao_pronta',
  'leitura_fechada',
  'item_fechado',
  'campo_invalido',
  'nada_para_trazer',
  'nao_pode_desfazer',
];

// O seguro mudou por outro caminho (outra pessoa, outra aba): o que a tela
// mostra já não vale, e ela relê o seguro depois de dizer o que houve.
const SEGURO_JA_MUDOU = [
  'ja_cancelado',
  'nao_cancelado',
  'sem_pdf',
  // #2898 — a renovação terminou, foi desfeita ou saiu do funil por outro
  // caminho; ou o seguro ganhou a apólice nova ou foi cancelado.
  'sem_renovacao',
  'ja_tem_desfecho',
  'sem_desfecho',
  'ja_tem_apolice_nova',
  'anterior_cancelada',
];

export const codigoDaRecusa = falha =>
  falha?.name === RECUSADO && CODIGOS_DE_RECUSA.includes(falha.codigo)
    ? falha.codigo
    : '';

export const seguroJaMudou = codigo => SEGURO_JA_MUDOU.includes(codigo);

// A chave da frase no catálogo; sem código conhecido, a frase de sempre de quem
// chamou (`padrao`).
export const chaveDaRecusa = (codigo, padrao) =>
  CODIGOS_DE_RECUSA.includes(codigo)
    ? `RELACIONAMENTOS_CARTEIRA.RECUSAS.${codigo.toUpperCase()}`
    : padrao;
