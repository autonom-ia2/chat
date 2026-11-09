require 'rails_helper'

# G46 (exemplo 14, passo 5): o card na etapa há `dias` dias sem o cliente mandar foto ou PDF. A conta começa na
# entrada na etapa e recomeça a cada documento; a marca é o instante do último, e uma consulta acha todos os cards.
RSpec.describe Autonomia::Automacao::Tempo::SemDocumento, :automacao_motor do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:funil) { create_crm_pipeline(account: account, user: admin).first }
  let(:etapa) { create_crm_stage(account: account, pipeline: funil, name: 'Documentação', position: 1) }
  let(:outra_etapa) { create_crm_stage(account: account, pipeline: funil, name: 'Emissão', position: 2) }
  let(:contato) { create(:contact, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato) }
  let(:gatilho) { { 'tipo' => 'card.sem_documento', 'etapa_id' => etapa.id, 'dias' => 2 } }
  let(:definicao) { travel_to(1.week.ago) { automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: gatilho) } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    definicao
  end

  def card_na_etapa(desde, contato: self.contato, etapa: self.etapa)
    card = account.crm_cards.create!(pipeline: funil, stage: etapa, contact: contato, title: 'Seguro', currency: 'BRL')
    card.update_columns(entered_stage_at: desde) # rubocop:disable Rails/SkipsModelValidations
    card
  end

  # O tipo do anexo, o content type, o arquivo de spec/assets e o meta de cada mídia.
  def midias
    {
      foto: [:image, 'image/png', 'sample.png', {}],
      pdf: [:file, 'application/pdf', 'sample.pdf', {}],
      audio: [:audio, 'audio/ogg', 'sample.ogg', {}],
      video: [:video, 'video/mp4', 'sample.mp4', {}],
      figurinha: [:image, 'image/webp', 'sample.png', { 'is_sticker' => true }],
      docx: [:file, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'sample.pdf', {}]
    }
  end

  def chega(midia, quando:, onde: conversa)
    file_type, content_type, arquivo, meta = midias.fetch(midia)
    mensagem = onde.messages.new(account: account, inbox: onde.inbox, message_type: :incoming, sender: onde.contact, content: nil,
                                 created_at: quando)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: file_type, meta: meta)
    anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: 'doc', content_type: content_type, identify: false)
    mensagem.save!
    mensagem.reload
  end

  def achados
    lista = []
    described_class.new(definicao: definicao.reload, gatilho: gatilho, agora: Time.current).cada { |card, marca| lista << [card.id, marca] }
    lista
  end

  def marca(card, desde) = "card.sem_documento:#{card.id}:#{desde.utc.iso8601(6)}"

  it 'a foto ou o PDF recomeça a conta, e a marca é o instante do último', :aggregate_failures do
    card = card_na_etapa(5.days.ago)
    chega(:foto, quando: 3.days.ago)
    pdf = chega(:pdf, quando: 2.days.ago - 1.hour)

    expect(achados).to eq([[card.id, marca(card, pdf.created_at)]])

    chega(:foto, quando: 1.day.ago)
    expect(achados).to eq([])
  end

  it 'texto, áudio, vídeo, figurinha e arquivo que não é PDF não recomeçam', :aggregate_failures do
    card = card_na_etapa(2.days.ago - 1.hour)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, sender: contato,
                     content: 'Já mando', created_at: 1.day.ago)
    %i[audio video figurinha docx].each { |midia| chega(midia, quando: 1.day.ago) }

    expect(achados).to eq([[card.id, marca(card, card.reload.entered_stage_at)]])
  end

  it 'o documento que a equipe mandou, ou de antes da entrada na etapa, não conta', :aggregate_failures do
    card = card_na_etapa(2.days.ago - 1.hour)
    chega(:pdf, quando: 10.days.ago)
    saida = conversa.messages.new(account: account, inbox: inbox, message_type: :outgoing, sender: admin, content: nil,
                                  created_at: 1.day.ago)
    saida.attachments.new(account_id: account.id, file_type: :file).file
         .attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'apolice.pdf', content_type: 'application/pdf')
    saida.save!

    expect(achados).to eq([[card.id, marca(card, card.reload.entered_stage_at)]])
  end

  it 'documento numa conversa que quem ligou não vê não conta' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: inbox)
    definicao.update_columns(ligada_por_id: agente.id) # rubocop:disable Rails/SkipsModelValidations
    card = card_na_etapa(2.days.ago - 1.hour)
    fora = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contato)
    chega(:pdf, quando: 1.day.ago, onde: fora)

    expect(achados).to eq([[card.id, marca(card, card.reload.entered_stage_at)]])
  end

  it 'só o card aberto, na etapa, e o sem contato conta da entrada', :aggregate_failures do
    sem_contato = card_na_etapa(2.days.ago - 1.hour, contato: nil)
    card_na_etapa(2.days.ago - 1.hour, etapa: outra_etapa)
    ganho = card_na_etapa(2.days.ago - 1.hour)
    ganho.update_columns(status: Crm::Card.statuses[:won]) # rubocop:disable Rails/SkipsModelValidations

    expect(achados).to eq([[sem_contato.id, marca(sem_contato, sem_contato.reload.entered_stage_at)]])
  end

  it 'acha todos os cards numa consulta só, sem uma ida ao banco por card' do
    contar = lambda do
      consultas = 0
      contador = ->(*, dados) { consultas += 1 unless dados[:name] == 'SCHEMA' || dados[:cached] }
      ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') { achados }
      consultas
    end
    card_na_etapa(2.days.ago - 1.hour)
    uma = contar.call
    3.times do
      outro = create(:contact, account: account)
      card_na_etapa(5.days.ago, contato: outro)
      chega(:pdf, quando: 2.days.ago - 1.hour, onde: create(:conversation, account: account, inbox: inbox, contact: outro))
    end

    expect([contar.call, achados.size]).to eq([uma, 4])
  end

  describe 'ao salvar' do
    it 'pede pelo menos 1 dia' do
      problemas = Autonomia::Automacao::ProblemasDoGatilho.new(gatilho.merge('dias' => 0), account).problemas

      expect(problemas).to eq([I18n.t('autonomia.automacao.receita.sem_documento_sem_dias')])
    end
  end
end
