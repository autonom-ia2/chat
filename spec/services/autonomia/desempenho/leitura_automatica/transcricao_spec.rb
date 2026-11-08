require 'rails_helper'

# A transcrição precisa ser a da prova cega (#2301): o formato exato, linha por linha. Conversa inventada.
RSpec.describe Autonomia::Desempenho::LeituraAutomatica::Transcricao do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:equipe) { create(:user, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, created_at: Time.utc(2026, 10, 20, 12, 59)) }

  def mensagem(tipo, minuto, texto, remetente: nil, privada: false)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: tipo, sender: remetente, private: privada,
                     content: texto, created_at: Time.utc(2026, 10, 20, 13, minuto))
  end

  it 'escreve cabeçalho, autores, nota interna, anexo e evento no formato da prova, em UTC' do
    conversa.update!(label_list: ['vip'])
    mensagens = [
      mensagem(:incoming, 0, '  Quero saber o prazo  '),
      mensagem(:outgoing, 1, 'O prazo é de 3 dias.', remetente: robo),
      mensagem(:activity, 2, "Conversa atribuída #{'x' * 200}"),
      mensagem(:activity, 3, ''),
      mensagem(:outgoing, 4, 'Vou conferir.', remetente: equipe, privada: true),
      mensagem(:outgoing, 5, 'Confirmado.', remetente: equipe),
      mensagem(:incoming, 6, nil)
    ]

    texto = described_class.new(conversa: conversa, mensagens: mensagens, remetentes: [['AgentBot', robo.id]], rotulo: 'ANA').texto

    expect(texto.split("\n")).to eq([
                                      "=== CONVERSA #{conversa.display_id} | criada 2026-10-20T12:59 | status 0 | etiquetas vip | msgs 7",
                                      '[10-20T13:00] CLIENTE: Quero saber o prazo',
                                      '[10-20T13:01] ANA: O prazo é de 3 dias.',
                                      "  (10-20T13:02 evento: #{"Conversa atribuída #{'x' * 200}"[0, 160]})",
                                      "[10-20T13:04] NOTA_INTERNA HUMANO#{equipe.id}: Vou conferir.",
                                      "[10-20T13:05] HUMANO#{equipe.id}: Confirmado.",
                                      '[10-20T13:06] CLIENTE: [anexo/sem texto]'
                                    ])
  end

  it 'o robô que não é o agente aparece pelo tipo e pelo id' do
    outro = create(:agent_bot, account: account)
    mensagens = [mensagem(:outgoing, 0, 'Oi', remetente: outro)]

    texto = described_class.new(conversa: conversa, mensagens: mensagens, remetentes: [['AgentBot', robo.id]], rotulo: 'AGENTE').texto

    expect(texto.split("\n").last).to eq("[10-20T13:00] AgentBot#{outro.id}: Oi")
  end
end
