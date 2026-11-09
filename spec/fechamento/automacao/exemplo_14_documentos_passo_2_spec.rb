require 'rails_helper'

# Fechamento do épico #2414 (#2570), exemplo 14 dos termos de aceite, passo 2 (#2716): "Documentação completa para
# emitir".
#
# > "Quando o cliente fecha, eu perco dias esperando documento. Quero que o sistema peça, confira e me avise só quando
# > estiver tudo certo." — Dona Cida, dona da corretora
#
# Passo 2 do termo: "A cada foto ou PDF que chega, a IA extrai, do que o leitor de mídia leu, qual documento é e se os
# dados dão para ler." O card está em "Documentação" (o começo do termo); "a cada" é uma segunda automação, que começa
# na mensagem e só segue com anexo e com o card da conversa em "Documentação" (#2716). Sem esse filtro a IA rodaria, e
# cobraria, em toda mensagem da conta. Os outros passos seguem no pendentes_spec.
RSpec.describe 'Fechamento #2414 · exemplo 14, passo 2: a cada documento, a IA confere qual é', :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:cida) { create(:user, account: account, role: :administrator, name: 'Dona Cida') }
  let(:cliente) { create(:contact, account: account, name: 'Marcos', phone_number: '+5511900000014') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: cliente, source_id: '5511900000014') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: cliente, contact_inbox: contact_inbox, status: :open) }
  let(:funil) { create_crm_pipeline(account: account, user: cida).first }
  let(:documentacao) { create_crm_stage(account: account, pipeline: funil, name: 'Documentação', position: 1) }
  let(:emissao) { create_crm_stage(account: account, pipeline: funil, name: 'Emissão', position: 2) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: documentacao, title: 'Seguro auto do Marcos', currency: 'BRL',
                              primary_conversation: conversa, contact: cliente, inbox: inbox)
  end

  let(:receita) do
    {
      gatilho: { tipo: 'mensagem.criada', filtros: [
        { campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' },
        { campo: { '$valor' => 'mensagem.tem_anexo' }, op: 'igual', valor: true },
        { campo: { '$valor' => 'card.etapa_id' }, op: 'igual', valor: documentacao.id }
      ] },
      passos: [{
        id: 'qual_documento', tipo: 'extrair', le: %w[anexos],
        campos: [
          { chave: 'documento', descricao: 'qual documento é: CNH, documento do carro ou comprovante de endereço',
            destino: 'conversa.atributos.documento_recebido' },
          { chave: 'legivel', descricao: 'se os dados do documento dão para ler: sim ou não, e o que não deu',
            destino: 'conversa.atributos.documento_legivel' }
        ]
      }]
    }
  end

  let(:automacao) { montar_automacao(cida, account, nome: 'Conferir cada documento', receita: receita) }

  let(:file_types) { { 'image/png' => :image, 'application/pdf' => :file, 'audio/mpeg' => :audio } }

  # O documento chega como o canal grava a mídia: a mensagem sem texto, com o arquivo, antes de os jobs rodarem.
  def cliente_manda(arquivo, tipo, nome)
    mensagem = conversa.messages.new(account: account, inbox: inbox, message_type: :incoming, sender: cliente, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: file_types.fetch(tipo))
    anexo.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: nome, content_type: tipo)
    mensagem.save!
    rodar_jobs
  end

  def atributos = conversa.reload.custom_attributes.slice('documento_recebido', 'documento_legivel')

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    %w[documento_recebido documento_legivel].each do |chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'text')
    end
    card
    emissao
    ligar_automacao(cida, account, automacao)
    clear_enqueued_jobs
    ia_responde(account, 'automacao_extrair' => { 'documento' => 'CNH', 'legivel' => 'sim' })
  end

  after { Current.reset }

  it 'a foto da CNH vai à IA, e a conversa guarda qual documento é e se dá para ler', :aggregate_failures do
    cliente_manda('sample.png', 'image/png', 'cnh-marcos.png')

    expect(historico_de(automacao)).to eq([['qual_documento', 'ok', nil]])
    expect(atributos).to eq('documento_recebido' => 'CNH', 'documento_legivel' => 'sim')
    foto = ia_recebeu.sole['input'].first['content'].find { |parte| parte['type'] == 'input_image' }
    expect(foto).to be_present
  end

  it 'a cada documento, de novo: o PDF que chega depois também é conferido', :aggregate_failures do
    cliente_manda('sample.png', 'image/png', 'cnh-marcos.png')
    cliente_manda('sample.pdf', 'application/pdf', 'documento-do-carro.pdf')

    expect(historico_de(automacao).map(&:first)).to eq(%w[qual_documento qual_documento])
    pdf = ia_recebeu.last['input'].first['content'].find { |parte| parte['type'] == 'input_file' }
    expect(pdf).to include('filename' => 'documento-do-carro.pdf')
  end

  it 'mensagem só de texto não chama a IA' do
    cliente_escreve(conversa, 'Já mando os documentos')

    expect([historico_de(automacao), ia_recebeu]).to eq([[], []])
  end

  # O termo fala em "foto ou PDF": o áudio do cliente não é documento e não chama a IA.
  it 'áudio não chama a IA' do
    cliente_manda('sample.mp3', 'audio/mpeg', 'audio.mp3')

    expect([historico_de(automacao), ia_recebeu]).to eq([[], []])
  end

  it 'com o card fora de "Documentação", o documento não chama a IA (nada é cobrado)', :aggregate_failures do
    Crm::Cards::Mover.new(card: card, actor: cida, target_stage: emissao).perform

    cliente_manda('sample.pdf', 'application/pdf', 'comprovante.pdf')

    expect(historico_de(automacao)).to eq([])
    expect(ia_recebeu).to eq([])
  end

  it 'conversa sem card não chama a IA' do
    card.destroy!

    cliente_manda('sample.pdf', 'application/pdf', 'comprovante.pdf')

    expect([historico_de(automacao), ia_recebeu]).to eq([[], []])
  end
end
