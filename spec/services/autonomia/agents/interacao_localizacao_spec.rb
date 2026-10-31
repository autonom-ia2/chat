require 'rails_helper'

# #1479 F2: o agente pede a localização do cliente (`interacao.tipo = localizacao`). Só com a flag
# `agentes_pedir_localizacao` na conta, por cima da Fase 2. O pedido sai como `location_request` (botão "Enviar
# localização" do WhatsApp) no WhatsApp oficial com a janela aberta; nos outros canais, a pergunta em texto.
RSpec.describe Autonomia::Agents::Interacao do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_pedir_localizacao') } }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox) }
  let(:pedido) do
    { 'tipo' => 'localizacao', 'header' => nil, 'pergunta' => 'Pode me mandar sua localização?', 'opcoes' => [], 'botao' => nil, 'link' => nil }
  end
  let(:localizacao) { described_class.do_modelo(pedido, enderecos: Set.new) }

  def janela_aberta(conversa = conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversa, inbox: conversa.inbox, account: account)
  end

  describe '.do_modelo' do
    it 'guarda só o tipo e a pergunta' do
      expect(localizacao).to eq('tipo' => 'localizacao', 'pergunta' => 'Pode me mandar sua localização?')
    end

    it 'sem pergunta não há pedido (o botão do WhatsApp precisa de um texto)' do
      expect(described_class.do_modelo(pedido.merge('pergunta' => ' '), enderecos: Set.new)).to be_nil
      expect(described_class.do_modelo(pedido.merge('pergunta' => nil), enderecos: Set.new)).to be_nil
    end
  end

  describe '.localizacao?' do
    it 'só com a Fase 2 e a flag da conta' do
      expect(described_class.localizacao?(account)).to be(true)
      expect(described_class.localizacao?(conta_da_fase2)).to be(false)
      sem_fase2 = conta_da_fase2(ligada: false).tap { |conta| conta.enable_features!('agentes_pedir_localizacao') }
      expect(described_class.localizacao?(sem_fase2)).to be(false)
    end

    it 'cada conta decide a sua: a flag de uma não liga a outra' do
      outra = conta_da_fase2
      expect([described_class.localizacao?(account), described_class.localizacao?(outra)]).to eq([true, false])
    end
  end

  describe 'schema' do
    it 'o schema de sempre não oferece o pedido; o com localização oferece' do
      expect(described_class::SCHEMA[:anyOf].first[:properties][:tipo][:enum]).to eq(%w[opcoes link])
      expect(described_class::SCHEMA_COM_LOCALIZACAO[:anyOf].first[:properties][:tipo][:enum]).to eq(%w[opcoes link localizacao])
    end
  end

  describe '.mensagem' do
    it 'WhatsApp oficial com a janela aberta: o botão nativo, com a resposta e a pergunta no corpo' do
      janela_aberta
      final = described_class.mensagem(localizacao, texto: 'Temos unidades em 3 bairros.', conversation: conversation)
      expect(final).to eq(content: "Temos unidades em 3 bairros.\n\nPode me mandar sua localização?",
                          rich_message: { 'type' => 'location_request' },
                          em_texto: "Temos unidades em 3 bairros.\n\nPode me mandar sua localização?")
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'location_request', conversation: conversation)).to eq(:native)
    end

    it 'a pergunta que a resposta já traz no fim não se repete' do
      janela_aberta
      final = described_class.mensagem(localizacao, texto: 'Certo! Pode me mandar sua localização?', conversation: conversation)
      expect(final[:content]).to eq('Certo! Pode me mandar sua localização?')
    end

    it 'sozinha (depois do áudio): a pergunta é o corpo' do
      janela_aberta
      expect(described_class.mensagem(localizacao, texto: nil, conversation: conversation)[:content]).to eq('Pode me mandar sua localização?')
    end

    it 'janela fechada na oficial: o formato fica para o envio decidir, e o texto é a pergunta' do
      final = described_class.mensagem(localizacao, texto: nil, conversation: conversation)
      expect(final[:em_texto]).to eq('Pode me mandar sua localização?')
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'location_request', conversation: conversation)).to eq(:text)
    end

    it 'caixa API (WAHA): sai a pergunta em texto, o cliente manda pelo clipe' do
      api = create(:channel_api, account: account)
      conversa = create(:conversation, account: account, inbox: api.inbox)
      final = described_class.mensagem(localizacao, texto: 'Oi.', conversation: conversa)
      expect(final[:em_texto]).to eq("Oi.\n\nPode me mandar sua localização?")
      expect(RichMessages.delivery_mode(inbox: api.inbox, type: 'location_request')).to eq(:text)
    end
  end

  describe '.nos_pedacos' do
    it 'a pergunta vai num pedaço a mais, com o pedido de localização' do
      janela_aberta
      pedacos = [{ 'text' => 'Temos unidades.', 'type' => 'text', 'delay_ms' => 0 }]
      final = described_class.nos_pedacos(pedacos, localizacao, conversation: conversation)
      expect(final.size).to eq(2)
      expect(final.last).to include('text' => 'Pode me mandar sua localização?', 'corpo' => 'Pode me mandar sua localização?',
                                    'rich_message' => { 'type' => 'location_request' })
    end
  end

  describe '.limpa' do
    it 'a pergunta passa pela mesma limpeza da resposta' do
      expect(described_class.limpa(localizacao, &:upcase)).to eq('tipo' => 'localizacao', 'pergunta' => 'PODE ME MANDAR SUA LOCALIZAÇÃO?')
    end
  end

  describe '.oferta_do_agente?' do
    it 'o pedido de localização deste agente conta como oferta dele (histórico e citação)' do
      robo = create(:agent_bot, account: account)
      agente = criar_principal(account)
      Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: robo)
      pedido_gravado = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: robo,
                                        content: 'Pode me mandar sua localização?',
                                        content_attributes: { 'autonomia_agent_id' => agente.id, 'rich_message' => { 'type' => 'location_request' } })
      expect(described_class.oferta_do_agente?(pedido_gravado, agent: agente)).to be(true)
    end
  end
end
