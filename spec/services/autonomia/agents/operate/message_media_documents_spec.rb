require 'rails_helper'

# PDF anexado na conversa (#319). O caso que motiva isto é a RENOVAÇÃO: o cliente manda a apólice e
# o agente para de interrogar. Medido em 04/09/2026 numa apólice de auto real (HDI, 4 páginas): a
# extração de texto recuperou classe de bônus, sinistros, seguradora anterior e a tabela de
# coberturas com franquia — por isso o caminho é TEXTO, não `input_file`.
RSpec.describe Autonomia::Agents::Operate::MessageMedia do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:processor) { Autonomia::Agents::Knowledge::Processors::Pdf }

  def message_with(file_type:, path: Rails.root.join('spec/assets/sample.pdf'), content_type: 'application/pdf')
    message = create(:message, account: account, conversation: conversation, inbox: inbox)
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: File.open(path), filename: File.basename(path), content_type: content_type)
    attachment.save!
    message
  end

  def extract_for(message)
    described_class.new(messages: [message], agent: agent).extract
  end

  it 'turns an attached PDF into text the agent can read' do
    # Arrange
    message = message_with(file_type: :file)

    # Act
    result = extract_for(message)

    # Assert
    expect(result.documents.size).to eq(1)
    expect(result.documents.first[:name]).to eq('sample.pdf')
    expect(result.documents.first[:text]).to be_present
  end

  it 'leaves images and audio alone — a PDF is a third channel, not a replacement' do
    # Arrange
    message = message_with(file_type: :file)

    # Act
    result = extract_for(message)

    # Assert
    expect(result.images).to be_empty
    expect(result.transcripts).to be_empty
    expect(result).not_to be_empty
  end

  it 'ignores a non-PDF attachment, because file_type :file is generic' do
    # Arrange — o Chatwoot marca planilha, zip e PDF todos como `file`; quem decide é o content-type
    message = message_with(file_type: :file, path: Rails.root.join('spec/assets/sample.png'),
                           content_type: 'image/png')

    # Act / Assert
    expect(extract_for(message).documents).to be_empty
  end

  it 'refuses an oversized PDF before downloading the blob' do
    # Arrange
    stub_const('Autonomia::Agents::Config::MAX_DOCUMENT_BYTES', 1)
    message = message_with(file_type: :file)

    # Act / Assert — o processor nem chega a ser construído
    expect(processor).not_to receive(:new)
    expect(extract_for(message).documents).to be_empty
  end

  it 'keeps the turn alive when the PDF cannot be read' do
    # Arrange — PDF corrompido é o caso comum; o agente segue e pergunta os dados na conversa
    message = message_with(file_type: :file)
    quebrado = instance_double(processor)
    allow(quebrado).to receive(:extract).and_raise(StandardError, 'pdf_parse_failed')
    allow(processor).to receive(:new).and_return(quebrado)

    # Act
    result = extract_for(message)

    # Assert
    expect(result.documents).to be_empty
    expect(result).to be_empty
  end

  it 'normalises the text, because a decomposed accent breaks every field search' do
    # Arrange — na apólice real o "ô" de bônus veio como o + acento combinante, e procurar por
    # "bônus" não casava. Sem NFC, a extração parece ter perdido o campo que ela recuperou.
    decomposto = 'Classe de Bônus : 09'.unicode_normalize(:nfd)
    allow(processor).to receive(:new).and_return(instance_double(processor, extract: decomposto))
    message = message_with(file_type: :file)

    # Act
    text = extract_for(message).documents.first[:text]

    # Assert
    expect(text).to eq('Classe de Bônus : 09')
    expect(text).not_to eq(decomposto)
  end

  # O OCR não tem teto de custo: rasteriza página por página a 300 DPI. Num turno com cliente
  # esperando e 120s de limite, um escaneado de poucos MB trava o atendimento. A base de
  # conhecimento continua com OCR — lá roda em job e ninguém espera.
  it 'never runs OCR in a live conversation' do
    # Arrange
    espiao = instance_double(processor, extract: 'texto')
    allow(processor).to receive(:new).and_return(espiao)
    message = message_with(file_type: :file)

    # Act
    extract_for(message)

    # Assert
    expect(processor).to have_received(:new).with(anything, ocr: false)
  end

  it 'gives up on a scanned PDF instead of holding the turn' do
    # Arrange — sem camada de texto e sem OCR, a extração volta vazia. O agente pede os dados,
    # que é exatamente o que ele fazia antes de existir leitura de PDF: zero regressão.
    allow(processor).to receive(:new).and_return(instance_double(processor, extract: '   '))
    message = message_with(file_type: :file)

    # Act / Assert
    expect(extract_for(message).documents).to be_empty
  end

  it 'caps how many documents one turn carries' do
    # Arrange
    message = create(:message, account: account, conversation: conversation, inbox: inbox)
    (Autonomia::Agents::Config::MAX_DOCUMENTS_PER_MESSAGE + 1).times do
      attachment = message.attachments.new(account_id: account.id, file_type: :file)
      attachment.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')),
                             filename: 'apolice.pdf', content_type: 'application/pdf')
      attachment.save!
    end

    # Act / Assert
    expect(extract_for(message).documents.size).to eq(Autonomia::Agents::Config::MAX_DOCUMENTS_PER_MESSAGE)
  end
end
