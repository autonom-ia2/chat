require 'rails_helper'

# #3198 — o copiloto da equipe lê o arquivo que alguém mandou na conversa. Sem IA de verdade: a visão e a transcrição
# são dublês; o PDF é lido de verdade (camada de texto, local).
RSpec.describe Autonomia::Copilot::MidiaDaConversa do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:legendas) { instance_double(Crm::Ai::VisionCaptioner, caption: 'foto de um boleto de 120 reais') }
  let(:midia) { described_class.new(account: account) }

  def mensagem(conteudo = nil)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: conteudo)
  end

  before do
    limpar_redis_do_leitor
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
    allow(Crm::Ai::VisionCaptioner).to receive(:new).and_return(legendas)
  end

  it 'reaproveita o texto que já está no anexo, sem pagar de novo', :aggregate_failures do
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    audio = anexar_audio(mensagem, meta: { 'transcribed_text' => 'quero cancelar o plano' })
    foto = anexar_imagem(mensagem, meta: { 'ai_caption' => 'carteira de motorista' })

    midia.ler_pendentes([audio.message, foto.message])

    expect(midia.texto(audio.message)).to eq('[Áudio: quero cancelar o plano]')
    expect(midia.texto(foto.message)).to eq('[Imagem: carteira de motorista]')
    expect(legendas).not_to have_received(:caption)
  end

  it 'lê agora, pelo leitor do CRM, a foto que ainda não foi lida, e grava no anexo', :aggregate_failures do
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    foto = anexar_imagem(mensagem)
    messages = [foto.message]

    midia.ler_pendentes(messages)

    expect(midia.texto(foto.message)).to eq('[Imagem: foto de um boleto de 120 reais]')
    expect(foto.reload.meta['ai_caption']).to eq('foto de um boleto de 120 reais')
  end

  it 'lê só as mensagens mais novas na hora' do
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    fotos = Array.new(described_class::MAX_MENSAGENS_LIDAS_NA_HORA + 1) { anexar_imagem(mensagem) }

    midia.ler_pendentes(fotos.map(&:message))

    lidas = fotos.map { |foto| foto.reload.meta['ai_caption'].present? }
    expect(lidas).to eq([false] + Array.new(described_class::MAX_MENSAGENS_LIDAS_NA_HORA, true))
  end

  it 'lê o PDF sem IA quando o leitor do CRM não leu', :aggregate_failures do
    pdf = anexar_pdf(mensagem, 'Apolice numero 123 vigente ate dezembro', nome: 'apolice.pdf')

    texto = midia.texto(pdf.message)

    expect(texto).to start_with('[Arquivo apolice.pdf: ')
    expect(texto).to include('Apolice numero 123 vigente ate dezembro')
  end

  it 'avisa o que não lê, em vez de esconder o arquivo', :aggregate_failures do
    video = mensagem.attachments.create!(account: account, file_type: :video, external_url: 'https://exemplo.invalid/v.mp4')
    foto = anexar_imagem(mensagem, meta: { 'crm_ai_image_done' => true })

    expect(midia.texto(video.message)).to eq("[Vídeo: #{described_class::VIDEO}]")
    expect(midia.texto(foto.message)).to eq("[Imagem: #{described_class::NAO_LIDO}]")
  end

  it 'corta o arquivo grande' do
    audio = anexar_audio(mensagem, meta: { 'transcribed_text' => 'a' * 5_000 })

    expect(midia.texto(audio.message).length).to be <= described_class::MAX_POR_ANEXO + '[Áudio: ]'.length
  end

  it 'sem a flag do leitor, não lê nem enfileira nada', :aggregate_failures do
    foto = anexar_imagem(mensagem)

    expect { midia.ler_pendentes([foto.message]) }.not_to have_enqueued_job(Crm::Ai::LerMidiaJob)
    expect(legendas).not_to have_received(:caption)
    expect(midia.texto(foto.message)).to eq("[Imagem: #{described_class::NAO_LIDO}]")
  end

  it 'falha na leitura vai ao rastreador de erros e não derruba o copiloto', :aggregate_failures do
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    foto = anexar_imagem(mensagem)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
    allow(Crm::Ai::LeitorDeMidia).to receive(:ler_em_linha).and_raise(ActiveRecord::StatementInvalid)

    expect { midia.ler_pendentes([foto.message]) }.not_to raise_error
    expect(rastreador).to have_received(:capture_exception)
    expect(midia.texto(foto.message)).to eq("[Imagem: #{described_class::NAO_LIDO}]")
  end
end
