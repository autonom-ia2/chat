require 'rails_helper'

# G46: `le: anexos_novos` lê só os anexos que o passo ainda não leu, entre dois marcos (Resposta.marco, a régua do
# G31), sem o teto das últimas mensagens. Assim o laço dos documentos do exemplo 14 nunca manda o mesmo anexo duas
# vezes à IA, e nada fica de fora com 6 ou mais documentos nem com o anexo de commit atrasado.
RSpec.describe Autonomia::Automacao::AnexosDaConversa do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:modelo) { Crm::Ai::Config::VISION_MODEL }
  let(:inicio) { 1.day.ago.change(usec: 0) }

  def pdf(nome, quando = Time.current)
    mensagem = create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: nil,
                                created_at: quando)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: nome, content_type: 'application/pdf')
    anexo.save!
    mensagem
  end

  def marco = Autonomia::Automacao::Resposta.marco(conversa.contact, admin)
  def nomes(lidos) = lidos.partes(modelo: modelo).pluck(:filename)
  def novos(depois_de, ate = marco) = described_class.new(conversa, novos: { depois_de: depois_de, ate: ate })

  it 'na primeira leitura, todos desde o começo da execução, sem o teto das últimas mensagens' do
    7.times { |indice| pdf("doc-#{indice}.pdf", inicio + indice.hours) }

    expect(nomes(novos(inicio - 1.minute))).to eq(Array.new(7) { |indice| "doc-#{indice}.pdf" })
  end

  it 'depois, só os que o marco anterior não viu; o já lido não volta à IA', :aggregate_failures do
    pdf('cnh.pdf', inicio)
    primeiro = marco
    pdf('crlv.pdf')
    segundo = marco

    expect(nomes(novos(primeiro, segundo))).to eq(%w[crlv.pdf])
    expect(novos(segundo).quantos).to eq(0)
  end

  it 'o anexo de commit atrasado (id de antes do marco, visível depois) entra na leitura seguinte, uma vez só', :aggregate_failures do
    atrasado = pdf('atrasado.pdf', 2.seconds.ago)
    visto = pdf('visto.pdf', 1.second.ago)
    # O marco tirado quando só o `visto` já aparecia: o `atrasado` tinha o id reservado, mas não estava comitado.
    sem_o_atrasado = { 'lido_ate' => visto.id, 'lido_em' => Time.current.iso8601(6), 'lidas_na_margem' => [visto.id] }
    expect(atrasado.id).to be < visto.id

    expect(nomes(novos(sem_o_atrasado))).to eq(%w[atrasado.pdf])
    expect(novos(marco).quantos).to eq(0)
  end

  it 'o que chega depois do marco desta leitura fica para a próxima', :aggregate_failures do
    pdf('cnh.pdf', inicio)
    desta = marco
    pdf('crlv.pdf')

    expect(nomes(novos(inicio - 1.minute, desta))).to eq(%w[cnh.pdf])
    expect(nomes(novos(desta))).to eq(%w[crlv.pdf])
  end

  def anexo(mensagem, arquivo, tipo, content_type, meta: {})
    item = mensagem.attachments.new(account_id: account.id, file_type: tipo, meta: meta)
    item.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: arquivo, content_type: content_type, identify: false)
    item.save!
    item
  end

  def mensagem = create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: nil)

  def motivos(lidos) = lidos.fora.map { |item| item.values_at('attachment_id', 'motivo') }

  it 'só foto e PDF que dá para mandar: o resto sai do conjunto, com qual e por quê, e a foto boa vai', :aggregate_failures do
    figurinha = anexo(mensagem, 'booking_small.webp', :image, 'image/webp', meta: { 'is_sticker' => true })
    sem_arquivo = anexo(mensagem, 'avatar.png', :image, 'image/png')
    ActiveStorage::Attachment.where(record: sem_arquivo).delete_all
    docx = anexo(mensagem, 'sample.pdf', :file, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    audio = anexo(mensagem, 'sample.ogg', :audio, 'audio/ogg')
    anexo(mensagem, 'avatar.png', :image, 'image/png')

    lidos = novos(inicio)

    expect(lidos.motivo(modelo: modelo)).to be_nil
    expect(lidos.partes(modelo: modelo).pluck(:type)).to eq(%w[input_image])
    expect(motivos(lidos)).to eq([[figurinha.id, 'nao_e_foto_nem_pdf'], [sem_arquivo.id, 'anexo_sem_leitura'],
                                  [docx.id, 'nao_e_foto_nem_pdf'], [audio.id, 'nao_e_foto_nem_pdf']])
    expect(lidos.fora.first['message_id']).to eq(figurinha.message_id)
    expect(lidos.para_depois).to eq(0)
  end

  it 'o arquivo que some entre a escolha e o envio sai do conjunto, e a foto boa da mesma leitura vai', :aggregate_failures do
    sumiu = anexo(mensagem, 'avatar.png', :image, 'image/png')
    anexo(mensagem, 'sample.pdf', :file, 'application/pdf')
    lidos = novos(inicio)
    expect(lidos.quantos).to eq(2)

    sumiu.file.blob.service.delete(sumiu.file.blob.key)

    expect(lidos.partes(modelo: modelo).pluck(:type)).to eq(%w[input_file])
    expect(motivos(lidos)).to eq([[sumiu.id, 'anexo_sem_leitura']])
  end

  it 'o que passa do teto somado (fotos e PDFs) fica para a próxima ida, sem se perder', :aggregate_failures do
    3.times { |indice| anexo(mensagem, 'avatar.png', :image, 'image/png').file.blob.update!(filename: "foto-#{indice}.png") }
    stub_const("#{described_class}::LIMITE_DOS_ARQUIVOS", 2 * File.size(Rails.root.join('spec/assets/avatar.png')))

    primeira = novos(inicio)
    expect([primeira.quantos, primeira.para_depois, primeira.fora]).to eq([2, 1, []])
    segunda = novos(primeira.marco_lido)

    expect([segunda.quantos, segunda.para_depois]).to eq([1, 0])
    expect(novos(segunda.marco_lido).quantos).to eq(0)
  end

  it 'a mensagem que sozinha passa do teto vai com os anexos que cabem; o resto dela sai, e a seguinte fica para depois',
     :aggregate_failures do
    grande = mensagem
    cabe = anexo(grande, 'avatar.png', :image, 'image/png')
    sobra = anexo(grande, 'avatar.png', :image, 'image/png')
    seguinte = anexo(mensagem, 'sample.pdf', :file, 'application/pdf')
    stub_const("#{described_class}::LIMITE_DOS_ARQUIVOS", File.size(Rails.root.join('spec/assets/avatar.png')) + 1)

    lidos = novos(inicio)

    expect(lidos.partes(modelo: modelo).pluck(:type)).to eq(%w[input_image])
    expect(motivos(lidos)).to eq([[sobra.id, 'passa_do_teto']])
    expect([lidos.para_depois, lidos.marco_lido['lido_ate']]).to eq([1, cabe.message_id])
    expect(nomes(novos(lidos.marco_lido))).to eq([seguinte.file.filename.to_s])
  end

  it 'sem `novos`, lê como `anexos`: as últimas mensagens; as duas leituras saem do Estado', :aggregate_failures do
    7.times { |indice| pdf("doc-#{indice}.pdf", inicio + indice.hours) }
    estado = Autonomia::Decisores::Estado.new(conversation: conversa, leituras: %w[mensagens_recentes])
    janela = { depois_de: inicio + 5.hours, ate: marco }

    expect(nomes(described_class.new(conversa))).to eq(%w[doc-2.pdf doc-3.pdf doc-4.pdf doc-5.pdf doc-6.pdf])
    expect(nomes(described_class.leitura(estado, { 'le' => %w[anexos_novos] }, conversa, novos: janela).anexos)).to eq(%w[doc-6.pdf])
    expect(described_class.leitura(estado, { 'le' => %w[anexos] }, conversa, novos: janela).anexos.quantos).to eq(5)
    expect(described_class.sem_anexos(%w[card anexos anexos_novos])).to eq(%w[card])
  end
end
