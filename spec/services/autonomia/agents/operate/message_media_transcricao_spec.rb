require 'rails_helper'

# IA entende a conversa F4 (revisão adversarial): o áudio é transcrito por dois consumidores, o leitor de mídia do CRM
# (Crm::Ai::LeitorDeMidia) e o turno dos Agentes. Os dois usam a mesma trava do anexo e relêem o cache sob ela antes de
# pagar: quem chega depois encontra o texto e não paga de novo.
RSpec.describe Autonomia::Agents::Operate::MessageMedia do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:transcricoes) { instance_double(Crm::Ai::TranscriptionClient, transcribe: 'texto pago') }
  let(:mensagem) { create(:message, account: account, conversation: conversation, inbox: inbox) }
  let!(:audio) do
    mensagem.attachments.create!(account: account, file_type: :audio, external_url: 'https://exemplo.invalid/audio.ogg')
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(transcricoes)
  end

  # Pega: o turno ler o anexo antes de o leitor do CRM gravar a transcrição e pagar a mesma transcrição de novo.
  it 'o anexo transcrito pelo outro consumidor depois da leitura não é pago de novo', :aggregate_failures do
    mensagem.attachments.load
    Attachment.find(audio.id).update!(meta: { 'transcribed_text' => 'texto do leitor do CRM' })

    resultado = described_class.new(messages: [mensagem], agent: agent).extract

    expect(resultado.transcripts).to eq(['texto do leitor do CRM'])
    expect(transcricoes).not_to have_received(:transcribe)
  end

  it 'sem cache, transcreve uma vez e guarda para o próximo', :aggregate_failures do
    described_class.new(messages: [mensagem], agent: agent).extract
    segunda = described_class.new(messages: [mensagem.reload], agent: agent).extract

    expect(segunda.transcripts).to eq(['texto pago'])
    expect(audio.reload.meta.to_h['transcribed_text']).to eq('texto pago')
    expect(transcricoes).to have_received(:transcribe).once
  end
end
