// Conversa aberta na campanha do WhatsApp oficial (#1335): quem do público
// falou com a caixa nas últimas 24 horas recebe uma mensagem escrita (sem
// modelo); os outros recebem o modelo. Não depende da tela de Modelos.
//
// Contrato (já no formato da tela):
// contarJanela({ publicoId, caixaId, categoria }) →
//   { dentro, fora, fechamLogo, conferidoEm (ISO),
//     precos: { modelo: { valor, moeda } | null, escrita: { valor, moeda } | null },
//     franquia: { limite, usadas } | null,
//     campos: [{ chave, rotulo }] }
// escrever({ publicoId, caixaId, categoria, objetivo, resposta, tom, base, melhoria }) →
//   { status: 'ok' | 'precisa_mais_info' | 'nao_se_aplica', opcoes: [{ texto }], pergunta }
//   Texto com os campos na sintaxe do catálogo ({{cliente.primeiro_nome}}).
import api from 'dashboard/api/conversaAberta';

const preco = item =>
  item ? { valor: Number(item.valor), moeda: item.moeda } : null;

const contarJanela = async ({ publicoId, caixaId, categoria }) => {
  const { data } = await api.contagem({
    campaignImportId: publicoId,
    inboxId: caixaId,
    categoria,
  });
  const payload = data.payload;
  return {
    dentro: payload.dentro,
    fora: payload.fora,
    fechamLogo: payload.fecham_logo,
    conferidoEm: payload.conferido_em,
    precos: {
      modelo: preco(payload.precos?.modelo),
      escrita: preco(payload.precos?.escrita),
    },
    franquia: payload.franquia || null,
    campos: payload.campos || [],
  };
};

const escrever = async ({ publicoId, caixaId, categoria, ...pedido }) => {
  const { data } = await api.escrever({
    campaign_import_id: publicoId,
    inbox_id: caixaId,
    categoria,
    objetivo: pedido.objetivo,
    resposta: pedido.resposta,
    tom: pedido.tom,
    base: pedido.base,
    melhoria: pedido.melhoria,
  });
  return data.payload;
};

export default { contarJanela, escrever };
