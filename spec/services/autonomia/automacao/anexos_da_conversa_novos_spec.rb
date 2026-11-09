require 'rails_helper'

# G46: `le: anexos_novos` lê só os anexos da pausa (o "esperar até" cumprido logo antes), sem o teto das últimas
# mensagens. Assim o laço dos documentos do exemplo 14 nunca manda o mesmo anexo duas vezes à IA, e nada fica de fora
# com 6 ou mais documentos.
RSpec.describe Autonomia::Automacao::AnexosDaConversa do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:modelo) { Crm::Ai::Config::VISION_MODEL }
  let(:inicio) { Time.zone.parse('2026-11-09 09:00') }

  def pdf(nome, quando)
    mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil, created_at: quando)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: nome, content_type: 'application/pdf')
    anexo.save!
  end

  def nomes(lidos) = lidos.partes(modelo: modelo).pluck(:filename)

  before { 7.times { |indice| pdf("doc-#{indice}.pdf", inicio + indice.hours) } }

  it 'na pausa, todos os que chegaram nela e só eles, depois do começo e até o fim' do
    pausa = (inicio + 1.hour)..(inicio + 5.hours)

    expect(nomes(described_class.new(conversa, pausa: pausa))).to eq(%w[doc-2.pdf doc-3.pdf doc-4.pdf doc-5.pdf])
  end

  it 'a pausa aberta lê todos desde o começo, sem o teto das últimas mensagens' do
    expect(nomes(described_class.new(conversa, pausa: (inicio - 1.minute)..))).to eq(Array.new(7) { |indice| "doc-#{indice}.pdf" })
  end

  it 'sem pausa, lê como `anexos`: as últimas mensagens' do
    expect(nomes(described_class.new(conversa))).to eq(%w[doc-2.pdf doc-3.pdf doc-4.pdf doc-5.pdf doc-6.pdf])
  end

  it 'a pausa só vale para quem lê `anexos_novos`; as duas leituras saem do Estado', :aggregate_failures do
    estado = Autonomia::Decisores::Estado.new(conversation: conversa, leituras: %w[mensagens_recentes])
    pausa = ((inicio + 5.hours)..)

    novos = described_class.leitura(estado, { 'le' => %w[anexos_novos] }, conversa, pausa: pausa).anexos
    antigos = described_class.leitura(estado, { 'le' => %w[anexos] }, conversa, pausa: pausa).anexos

    expect([nomes(novos), antigos.quantos]).to eq([%w[doc-6.pdf], 5])
    expect(described_class.sem_anexos(%w[card anexos anexos_novos])).to eq(%w[card])
  end
end
