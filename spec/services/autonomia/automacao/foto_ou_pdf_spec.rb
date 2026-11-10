require 'rails_helper'

# A régua do documento do ex.14 ("foto ou PDF") num lugar só: `anexo?`/`mensagem?` em Ruby (o filtro
# `mensagem.tem_anexo`, #2716) e `escopo` em SQL (o "esperar até" do documento novo, G46). As duas respondem igual.
RSpec.describe Autonomia::Automacao::FotoOuPdf do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }

  # [file_type, content_type, arquivo de spec/assets, nome, meta]
  def tipos
    {
      foto: [:image, 'image/png', 'sample.png', 'cnh.png', {}],
      pdf: [:file, 'application/pdf', 'sample.pdf', 'crlv.pdf', {}],
      figurinha: [:image, 'image/webp', 'sample.png', 'figurinha.webp', { 'is_sticker' => true }],
      docx: [:file, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'sample.pdf', 'proposta.docx', {}],
      audio: [:audio, 'audio/ogg', 'sample.ogg', 'ja-mando.ogg', {}]
    }
  end

  def mensagem_com(*midias)
    mensagem = conversa.messages.new(account: account, inbox: conversa.inbox, message_type: :incoming, content: nil)
    midias.each do |midia|
      file_type, content_type, arquivo, nome, meta = tipos.fetch(midia)
      anexo = mensagem.attachments.new(account_id: account.id, file_type: file_type, meta: meta)
      anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: nome, content_type: content_type, identify: false)
    end
    mensagem.tap(&:save!)
  end

  def no_escopo?(mensagem) = described_class.escopo(Message.where(id: mensagem.id)).exists?

  it 'foto e PDF são documento, em Ruby e em SQL', :aggregate_failures do
    %i[foto pdf].each do |midia|
      mensagem = mensagem_com(midia)
      expect([midia, described_class.mensagem?(mensagem), no_escopo?(mensagem)]).to eq([midia, true, true])
    end
  end

  it 'figurinha, docx e áudio não são, em Ruby e em SQL', :aggregate_failures do
    %i[figurinha docx audio].each do |midia|
      mensagem = mensagem_com(midia)
      expect([midia, described_class.mensagem?(mensagem), no_escopo?(mensagem)]).to eq([midia, false, false])
    end
  end

  it 'a mensagem só de texto não é; com um áudio e uma foto, é', :aggregate_failures do
    texto = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'já mando')

    expect([described_class.mensagem?(texto), no_escopo?(texto)]).to eq([false, false])
    expect(no_escopo?(mensagem_com(:audio, :foto))).to be(true)
  end

  it 'o escopo é uma consulta só, sem carregar anexo' do
    3.times { mensagem_com(:foto) }

    consultas = []
    contar = ->(*, payload) { consultas << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { described_class.escopo(conversa.messages).count }

    expect(consultas.size).to eq(1)
  end
end
