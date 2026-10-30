require 'rails_helper'

# IA entende a conversa F4: o texto de cada anexo como as IAs do CRM o leem, uma fonte só.
RSpec.describe Crm::Ai::TextoDaMidia do
  let(:account) { create(:account) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:mensagem) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }

  describe '.fragmento' do
    it 'áudio e foto como antes (lidos e não lidos)', :aggregate_failures do
      expect(described_class.fragmento(anexar_audio(mensagem, meta: { 'transcribed_text' => 'oi' }))).to eq('[áudio transcrito]: oi')
      expect(described_class.fragmento(anexar_audio(mensagem))).to eq('[áudio recebido, não transcrito]')
      expect(described_class.fragmento(anexar_imagem(mensagem, meta: { 'ai_caption' => 'uma foto' }))).to eq('[imagem]: uma foto')
      expect(described_class.fragmento(anexar_imagem(mensagem))).to eq('[imagem recebida]')
    end

    it 'PDF sem `pdf: true` é só "documento recebido", mesmo lido' do
      pdf = anexar_pdf(mensagem, 'texto')
      pdf.update!(meta: { 'ai_text' => 'texto lido', 'crm_ai_pdf_done' => true })

      expect(described_class.fragmento(pdf)).to eq('[documento recebido]')
    end

    it 'PDF com `pdf: true`: o nome e o texto lido, cortado no teto', :aggregate_failures do
      pdf = anexar_pdf(mensagem, 'texto', nome: 'proposta.pdf')
      pdf.update!(meta: { 'ai_text' => 'x' * 2_000, 'crm_ai_pdf_done' => true })

      fragmento = described_class.fragmento(pdf, pdf: true)

      expect(fragmento).to start_with('[documento proposta.pdf]: xxx')
      expect(fragmento.length).to eq('[documento proposta.pdf]: '.length + described_class::MAX_CARACTERES_DO_PDF)
    end

    it 'PDF lido sem texto diz isso; não lido segue "documento recebido"', :aggregate_failures do
      lido = anexar_pdf(mensagem, nil, nome: 'scan.pdf')
      lido.update!(meta: { 'crm_ai_pdf_done' => true })

      expect(described_class.fragmento(lido, pdf: true)).to eq('[documento scan.pdf: sem texto legível]')
      expect(described_class.fragmento(anexar_pdf(mensagem, 'a'), pdf: true)).to eq('[documento recebido]')
    end
  end

  describe '.lido' do
    it 'só o anexo com texto lido; o resto é nil', :aggregate_failures do
      expect(described_class.lido(anexar_imagem(mensagem, meta: { 'ai_caption' => 'foto' }))).to eq('[imagem]: foto')
      expect(described_class.lido(anexar_imagem(mensagem, meta: { 'crm_ai_image_done' => true }))).to be_nil
      expect(described_class.lido(anexar_audio(mensagem))).to be_nil
      expect(described_class.lido(anexar_pdf(mensagem, 'a'))).to be_nil
    end
  end
end
