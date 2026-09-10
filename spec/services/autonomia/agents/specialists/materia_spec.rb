require 'rails_helper'

# A MATÉRIA QUE O ESPECIALISTA LÊ ALÉM DO BILHETE (entrega 1): a conversa e os documentos, sob os
# mesmos tetos e a mesma cerca do principal — e NADA que o cliente não tenha escrito ou anexado.
#
# PROVA POR MUTAÇÃO (10/09/2026): tirar o histórico de `mensagens` reprova "a conversa vem antes";
# capar pelo mais recente em vez do mais antigo reprova "o que sai é o mais antigo"; incluir nota
# privada na busca de anexos reprova "só mensagens públicas do cliente"; sem `uniq` reprova "o mesmo
# arquivo não entra duas vezes".
RSpec.describe Autonomia::Agents::Specialists::Materia do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 999_999)
  end
  let(:historico) do
    [{ role: 'user', content: 'Quero cotar meu carro' }, { role: 'assistant', content: 'Qual é o CPF do titular?' },
     { role: 'user', content: '04297912678' }]
  end

  def textos(mensagens)
    mensagens.map { |m| m[:content].first[:text] }
  end

  it 'a conversa vem antes, com as duas vozes e um aviso de que e dado para leitura' do
    mensagens = described_class.new(delivery: delivery, history: historico).mensagens

    expect(mensagens.map { |m| m[:role] }).to eq(%w[user user assistant user])
    expect(textos(mensagens).first).to include('CONVERSA ATÉ AQUI')
    expect(textos(mensagens)).to include('04297912678', 'Qual é o CPF do titular?')
    expect(mensagens[2][:content].first[:type]).to eq('output_text')
  end

  it 'sem conversa nem documento, nao poe nada: o bilhete sozinho continua valendo' do
    expect(described_class.new(delivery: delivery).mensagens).to eq([])
  end

  it 'o historico tem teto, e o que sai e o mais antigo' do
    grande = Array.new(40) { |i| { role: 'user', content: "mensagem #{i} #{'x' * 3_000}" } }

    mensagens = described_class.new(delivery: delivery, history: grande).mensagens
    corpo = textos(mensagens).drop(1)

    expect(corpo.size).to be < 40
    expect(corpo.last).to start_with('mensagem 39')
    expect(corpo.first).not_to start_with('mensagem 0 ')
    expect(corpo.sum(&:length)).to be <= Autonomia::Agents::Config::MAX_HISTORY_TOTAL_CHARS
  end

  it 'os documentos deste turno vem cercados, com a mesma moldura do principal' do
    mensagens = described_class.new(delivery: delivery, documents: [{ name: 'apolice.pdf', text: 'Classe de bônus: 5' }]).mensagens

    expect(textos(mensagens).last).to include('DOCUMENTOS ANEXADOS PELO CLIENTE', '<documento nome="apolice.pdf">', 'Classe de bônus: 5')
  end

  describe 'os PDFs das mensagens anteriores do cliente' do
    let(:media) { instance_double(Autonomia::Agents::Operate::MessageMedia) }

    def mensagem_com_anexo(privada: false, incoming: true)
      m = create(:message, conversation: conversation, account: account, inbox: inbox,
                           message_type: incoming ? :incoming : :outgoing, private: privada, content: 'segue a apólice')
      anexo = m.attachments.new(account_id: account.id, file_type: :file)
      anexo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'apolice.pdf',
                        content_type: 'application/pdf')
      anexo.save!
      m
    end

    it 'entram depois dos deste turno, sem repetir o mesmo arquivo, com teto de tres' do
      anterior = mensagem_com_anexo
      allow(Autonomia::Agents::Operate::MessageMedia).to receive(:new).and_return(media)
      allow(media).to receive(:documents).and_return([{ name: 'apolice.pdf', text: 'de antes' }, { name: 'crlv.pdf', text: 'crlv' },
                                                      { name: 'outro.pdf', text: 'outro' }])
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: anterior.id + 1)

      docs = described_class.new(delivery: delivery, documents: [{ name: 'apolice.pdf', text: 'deste turno' }], agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(%w[apolice.pdf crlv.pdf outro.pdf])
      expect(docs.first[:text]).to eq('deste turno')
      expect(Autonomia::Agents::Operate::MessageMedia).to have_received(:new) do |messages:, **|
        expect(messages.map(&:id)).to eq([anterior.id])
      end
    end

    it 'so mensagens publicas do cliente, anteriores a que abriu o turno' do
      privada = mensagem_com_anexo(privada: true)
      do_atendente = mensagem_com_anexo(incoming: false)
      do_cliente = mensagem_com_anexo
      deste_turno = mensagem_com_anexo
      allow(Autonomia::Agents::Operate::MessageMedia).to receive(:new).and_return(media)
      allow(media).to receive(:documents).and_return([])
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: deste_turno.id)

      described_class.new(delivery: delivery, agent: agent).documentos

      expect(Autonomia::Agents::Operate::MessageMedia).to have_received(:new) do |messages:, **|
        expect(messages.map(&:id)).to eq([do_cliente.id])
        expect(messages.map(&:id)).not_to include(privada.id, do_atendente.id, deste_turno.id)
      end
    end

    it 'falha na extracao nao derruba o especialista: segue sem os anteriores' do
      mensagem_com_anexo
      allow(Autonomia::Agents::Operate::MessageMedia).to receive(:new).and_raise('blob sumiu')

      expect(described_class.new(delivery: delivery, documents: [{ name: 'a.pdf', text: 'x' }], agent: agent).documentos.size).to eq(1)
    end
  end
end
