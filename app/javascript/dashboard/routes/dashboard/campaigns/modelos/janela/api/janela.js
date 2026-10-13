// Conversa aberta na campanha do WhatsApp oficial (#1335): quem do público falou
// com a caixa nas últimas 24 horas recebe uma mensagem escrita (sem modelo); os
// outros recebem o modelo. PROTÓTIPO: os dados vêm do adaptador falso. Para
// ligar no backend, troque a linha do import pelo adaptador HTTP.
//
// Contrato (já no formato da tela):
// contarJanela({ publicoId, caixaId, total }) →
//   { dentro, fora, fechamLogo, conferidoEm (ISO) }
//   dentro: quem tem mensagem recebida nesta caixa nas últimas 24 h;
//   fechamLogo: dos `dentro`, quantos saem da janela nas próximas 2 h.
// escrever({ caixaId, objetivo, tom, base, pedido, quantos }) →
//   { status: 'ok' | 'precisa_mais_info' | 'nao_se_aplica',
//     opcoes: [{ texto }], pergunta }
//   Texto com os campos na sintaxe do catálogo ({{cliente.primeiro_nome}}).
//   No backend: Ai::Redacao::Escrever, canal whatsapp_texto.
import adaptador from './adaptadorFalso';

export default adaptador;
