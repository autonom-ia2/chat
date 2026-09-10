require 'rails_helper'

# A MATÉRIA QUE O ESPECIALISTA LÊ ALÉM DO BILHETE (entrega 1): a conversa e os documentos, sob os
# mesmos tetos, a mesma cerca e o MESMO desligamento de mídia do principal — e nada que o cliente
# não tenha visto ou anexado nesta conversa.
#
# PROVA POR MUTAÇÃO (10/09/2026): tirar o histórico de `mensagens` reprova "a conversa vem antes";
# capar pelo mais recente reprova "o que sai é o mais antigo"; incluir nota privada na busca de
# anexos reprova "só mensagens públicas do cliente"; tirar a exclusão do que já entrou, ou o `uniq`
# por conteúdo, reprova "não lê de novo"; ignorar as vagas reprova "preenchem só as vagas"; deixar
# um PDF ilegível ocupar vaga reprova "não ocupa vaga"; tirar o portão reprova "mídia desligada";
# contar a duplicata deste turno reprova "conta uma vaga"; tirar o teto de tentativas reprova "tem teto".
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
    let(:processor) { Autonomia::Agents::Knowledge::Processors::Pdf }
    let(:pdf) { File.binread(Rails.root.join('spec/assets/sample.pdf')) }

    # O extrator devolve o texto pelo nome do arquivo, para distinguir os PDFs sem precisar de um PDF
    # real por caso; um nome que começa com "vazio" simula o escaneado sem camada de texto.
    before do
      allow(processor).to receive(:new) do |source, **|
        instance_double(processor, extract: source.reference.start_with?('vazio') ? '' : "texto de #{source.reference}")
      end
    end

    # `variante` muda os bytes (logo o checksum) sem mudar o que o extrator devolve.
    def anexar(nome, variante: nil, privada: false, incoming: true)
      m = create(:message, conversation: conversation, account: account, inbox: inbox,
                           message_type: incoming ? :incoming : :outgoing, private: privada, content: 'segue')
      anexo = m.attachments.new(account_id: account.id, file_type: :file)
      anexo.file.attach(io: StringIO.new([pdf, variante].compact.join), filename: nome, content_type: 'application/pdf')
      anexo.save!
      anexo
    end

    # O que o principal extraiu neste turno, pelo caminho dele (`Responder#media` -> `extract`).
    def lidos_pelo_principal(*anexos)
      Autonomia::Agents::Operate::MessageMedia.new(messages: anexos.map(&:message), agent: agent).extract.documents
    end

    def turno_aberto_por(message_id)
      Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: message_id)
    end

    it 'os deste turno primeiro; os anteriores preenchem so as vagas que sobram, do mais recente ao mais antigo' do
      anexar('velha.pdf', variante: '1')
      anexar('meio.pdf', variante: '2')
      anexar('nova.pdf', variante: '3')
      atual = anexar('atual.pdf')

      docs = described_class.new(delivery: turno_aberto_por(atual.message_id), documents: lidos_pelo_principal(atual),
                                 agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(%w[atual.pdf nova.pdf meio.pdf])
      expect(docs.last[:text]).to eq('texto de meio.pdf')
    end

    it 'nao le de novo o que ja entrou neste turno, nem o mesmo arquivo mandado duas vezes' do
      anexar('crlv.pdf', variante: 'c')
      anexar('crlv-de-novo.pdf', variante: 'c') # mesmo conteúdo, outro anexo, outro nome
      anexar('apolice-de-novo.pdf')                   # mesmo conteúdo do PDF deste turno
      atual = anexar('apolice.pdf')                   # veio no debounce, ANTES da mensagem que abriu o turno
      abriu = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'cota aí')
      deste_turno = lidos_pelo_principal(atual)

      docs = described_class.new(delivery: turno_aberto_por(abriu.id), documents: deste_turno, agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(%w[apolice.pdf crlv-de-novo.pdf])
      # uma extração para o principal (apolice.pdf) e UMA para o especialista (crlv-de-novo.pdf)
      expect(processor).to have_received(:new).twice
    end

    it 'a mesma apolice mandada duas vezes no debounce conta uma vaga' do
      anexar('cnh.pdf', variante: 'h')
      anexar('crlv.pdf', variante: 'c')
      primeira = anexar('apolice.pdf')
      segunda = anexar('apolice (1).pdf') # o cliente mandou de novo, no mesmo turno
      abriu = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'cota aí')
      deste_turno = lidos_pelo_principal(primeira, segunda)
      expect(deste_turno.size).to eq(2) # o principal não deduplica

      docs = described_class.new(delivery: turno_aberto_por(abriu.id), documents: deste_turno, agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(['apolice.pdf', 'crlv.pdf', 'cnh.pdf'])
    end

    it 'o numero de extracoes por chamada tem teto: a espera do cliente e limitada' do
      anexar('apolice.pdf')
      7.times { |i| anexar("vazio-#{i}.pdf", variante: "v#{i}") } # sete escaneados mais recentes que a apólice

      docs = described_class.new(delivery: delivery, agent: agent).documentos

      expect(docs).to eq([])
      expect(processor).to have_received(:new).exactly(described_class::TENTATIVAS).times
    end

    it 'um PDF sem camada de texto nao ocupa vaga: o extrator segue ate achar um legivel' do
      anexar('apolice.pdf')
      anexar('vazio-1.pdf', variante: 'v1')
      anexar('vazio-2.pdf', variante: 'v2')
      anexar('vazio-3.pdf', variante: 'v3') # os três mais recentes são escaneados sem texto

      docs = described_class.new(delivery: delivery, agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(['apolice.pdf'])
      expect(processor).to have_received(:new).exactly(4).times
    end

    it 'com a midia desligada, o especialista tambem nao le anexos anteriores' do
      anexar('apolice.pdf')

      docs = with_modified_env(AI_AGENT_MEDIA: 'false') do
        described_class.new(delivery: delivery, documents: [{ name: 'a.pdf', text: 'x' }], agent: agent).documentos
      end

      expect(docs.map { |d| d[:name] }).to eq(['a.pdf'])
      expect(processor).not_to have_received(:new)
    end

    it 'so mensagens publicas do cliente, anteriores a que abriu o turno' do
      anexar('privada.pdf', variante: 'p', privada: true)
      anexar('do-atendente.pdf', variante: 'a', incoming: false)
      anexar('do-cliente.pdf', variante: 'c')
      deste_turno = anexar('deste-turno.pdf', variante: 't')

      docs = described_class.new(delivery: turno_aberto_por(deste_turno.message_id), agent: agent).documentos

      expect(docs.map { |d| d[:name] }).to eq(['do-cliente.pdf'])
    end

    it 'falha na extracao nao derruba o especialista: segue sem os anteriores' do
      anexar('apolice.pdf')
      allow(Autonomia::Agents::Operate::MessageMedia).to receive(:new).and_raise('blob sumiu')

      expect(described_class.new(delivery: delivery, documents: [{ name: 'a.pdf', text: 'x' }], agent: agent).documentos.size).to eq(1)
    end
  end
end
