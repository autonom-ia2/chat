require 'rails_helper'

# #1702 — encaminhar mensagens como no WhatsApp: cópia enviada em cada destino, com a marca de encaminhada.
describe ConversaCanal::Encaminhamento do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caixa) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:origem) { create(:conversation, account: account, inbox: caixa) }
  let(:destino) { create(:conversation, account: account, inbox: caixa) }
  let(:outro_destino) { create(:conversation, account: account, inbox: caixa) }
  let!(:texto) { create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: 'Oi, tudo bem?') }

  def encaminhar(ids, destinos = [destino])
    described_class.new(origem: origem, message_ids: ids, destinos: destinos, user: agente).perform
  end

  def copias_em(conversa)
    conversa.messages.where("content_attributes::text LIKE '%forwarded%'")
  end

  def anexo(mensagem, tipo, arquivo: 'avatar.png', mime: 'image/png', meta: {})
    mensagem.attachments.create!(account_id: account.id, file_type: tipo, meta: meta,
                                 file: fixture_file_upload(Rails.root.join("spec/assets/#{arquivo}"), mime))
  end

  it 'cria em cada destino uma cópia enviada pelo atendente, com a marca e a origem' do
    resultado = encaminhar([texto.id], [destino, outro_destino])

    expect(resultado).to eq([{ conversation_id: destino.display_id, ok: true, erro: nil },
                             { conversation_id: outro_destino.display_id, ok: true, erro: nil }])
    copia = copias_em(destino).sole
    expect(copia).to have_attributes(content: 'Oi, tudo bem?', message_type: 'outgoing', sender: agente, private: false)
    expect(copia.content_attributes['forwarded']).to be(true)
    expect(copia.content_attributes['forwarded_from']).to eq('conversation_id' => origem.display_id, 'message_id' => texto.id)
    expect(copias_em(outro_destino).count).to eq(1)
  end

  it 'manda pelo caminho de envio de sempre (SendReplyJob)' do
    expect { encaminhar([texto.id]) }.to have_enqueued_job(SendReplyJob)
  end

  it 'reaproveita o blob do anexo, sem subir o arquivo de novo' do
    foto = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil)
    original = anexo(foto, :image)

    expect { encaminhar([foto.id]) }.not_to change(ActiveStorage::Blob, :count)

    copiado = copias_em(destino).sole.attachments.sole
    expect(copiado.file.blob.id).to eq(original.file.blob.id)
    expect(copiado.file_type).to eq('image')
  end

  it 'apagar a original não apaga o arquivo da cópia (o blob com outro anexo não é purgado)' do
    foto = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil)
    anexo(foto, :image)
    encaminhar([foto.id])
    copiado = copias_em(destino).sole.attachments.sole

    perform_enqueued_jobs { foto.destroy! }

    expect(ActiveStorage::PurgeJob).to have_been_performed
    expect(copiado.reload.file).to be_attached
    expect(copiado.file.blob.service.exist?(copiado.file.blob.key)).to be(true)
  end

  it 'documento continua documento e áudio de voz continua de voz' do
    mensagem = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil)
    anexo(mensagem, :audio, arquivo: 'sample.ogg', mime: 'audio/ogg', meta: { 'is_voice_message' => true })

    encaminhar([mensagem.id])

    expect(copias_em(destino).sole.attachments.sole.meta).to include('is_voice_message' => true)
  end

  it 'mantém a ordem das mensagens marcadas' do
    segunda = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, content: 'Segunda')

    encaminhar([segunda.id, texto.id])

    expect(copias_em(destino).pluck(:content)).to eq(['Oi, tudo bem?', 'Segunda'])
  end

  it 'localização do cliente sai como envio rico de localização' do
    lugar = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil,
                             content_attributes: { 'shared_location' => { 'latitude' => -23.55, 'longitude' => -46.63, 'name' => 'Sé' } })

    encaminhar([lugar.id])

    copia = copias_em(destino).sole
    expect(copia.content).to eq('')
    expect(copia.content_attributes['rich_message']).to eq('type' => 'location', 'latitude' => -23.55, 'longitude' => -46.63, 'name' => 'Sé')
  end

  it 'contato do cliente vira cartão de contato' do
    cartao = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil)
    cartao.attachments.create!(account_id: account.id, file_type: :contact, fallback_title: '5511999990000',
                               meta: { 'firstName' => 'Ana', 'lastName' => 'Souza' })

    encaminhar([cartao.id])

    expect(copias_em(destino).sole.content_attributes['rich_message'])
      .to eq('type' => 'contact', 'name' => 'Ana Souza', 'phone' => '+5511999990000', 'wa_id' => '5511999990000')
  end

  it 'localização mandada pela empresa copia o rich_message' do
    rico = { 'type' => 'location', 'latitude' => 1.5, 'longitude' => 2.5, 'name' => 'Loja' }
    enviada = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, content: '',
                               content_attributes: { 'rich_message' => rico })

    encaminhar([enviada.id])

    expect(copias_em(destino).sole.content_attributes['rich_message']).to eq(rico)
  end

  it 'recusa quem não é pessoa (robô)' do
    robo = create(:agent_bot, account: account)

    expect { described_class.new(origem: origem, message_ids: [texto.id], destinos: [destino], user: robo).perform }
      .to raise_error(described_class::Recusa, I18n.t('conversa_canal.encaminhar.so_pessoa'))
    expect(copias_em(destino)).to be_empty
  end

  describe 'o que não se encaminha' do
    it 'nota privada' do
      nota = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, private: true, content: 'só nós')

      expect { encaminhar([nota.id]) }.to raise_error(described_class::Recusa)
      expect(copias_em(destino)).to be_empty
    end

    it 'mensagem apagada' do
      texto.update!(content_attributes: { 'deleted' => true })

      expect { encaminhar([texto.id]) }.to raise_error(described_class::Recusa)
    end

    it 'mensagem apagada pelo cliente (o conteúdo fica guardado, mas não sai)' do
      texto.update!(content_attributes: { 'deleted_by_contact_at' => Time.current.iso8601 })

      expect { encaminhar([texto.id]) }.to raise_error(described_class::Recusa)
    end

    it 'mensagem não suportada' do
      texto.update!(content_attributes: { 'is_unsupported' => true })

      expect { encaminhar([texto.id]) }.to raise_error(described_class::Recusa)
    end

    it 'mídia de visualização única' do
      foto = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: nil)
      anexo(foto, :image, meta: { 'is_view_once' => true })

      expect { encaminhar([foto.id]) }.to raise_error(described_class::Recusa)
    end

    it 'mensagem de outra conversa' do
      alheia = create(:message, account: account, inbox: caixa, conversation: destino, message_type: :incoming, content: 'de lá')

      expect { encaminhar([alheia.id]) }.to raise_error(described_class::Recusa)
    end

    it 'mais de 5 destinos' do
      destinos = create_list(:conversation, 6, account: account, inbox: caixa)

      expect { encaminhar([texto.id], destinos) }.to raise_error(described_class::Recusa, /5/)
    end

    it 'mais de 30 mensagens' do
      ids = (1..31).to_a

      expect { encaminhar(ids) }.to raise_error(described_class::Recusa, /30/)
    end
  end

  context 'with destino fora da janela de 24 h (API oficial)' do
    let(:canal_oficial) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    end
    let(:fechado) { create(:conversation, account: account, inbox: canal_oficial.inbox) }

    it 'não cria a cópia e devolve o motivo só para aquele destino' do
      create(:message, account: account, inbox: canal_oficial.inbox, conversation: fechado, message_type: :incoming,
                       created_at: 2.days.ago)

      resultado = encaminhar([texto.id], [fechado, destino])

      expect(resultado.first).to include(conversation_id: fechado.display_id, ok: false)
      expect(resultado.first[:erro]).to eq(I18n.t('conversa_canal.encaminhar.fora_da_janela'))
      expect(resultado.last).to include(ok: true)
      expect(copias_em(fechado)).to be_empty
    end
  end

  # Teste de estresse do #1702 (17/10): a cópia desfeita fica pendurada em destino.messages (autosave) e um save
  # posterior do mesmo objeto a gravaria sem validação.
  it 'lote desfeito não volta num save posterior do destino' do
    segunda = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: 'Segunda')

    with_modified_env CONVERSATION_MESSAGE_PER_MINUTE_LIMIT: '1' do
      expect(encaminhar([texto.id, segunda.id]).first).to include(ok: false)
    end
    destino.update!(updated_at: Time.current)

    expect(copias_em(destino)).to be_empty
  end

  it 'falha inesperada num destino fica nele: os outros seguem' do
    falha = create(:conversation, account: account, inbox: caixa)
    original = Messages::MessageBuilder.method(:new)
    allow(Messages::MessageBuilder).to receive(:new) do |user, conversa, params|
      raise ArgumentError, 'quebrou' if conversa == falha

      original.call(user, conversa, params)
    end

    resultado = encaminhar([texto.id], [falha, destino])

    expect(resultado.first).to include(conversation_id: falha.display_id, ok: false)
    expect(resultado.first[:erro]).to eq(I18n.t('conversa_canal.encaminhar.falhou'))
    expect(resultado.last).to include(ok: true)
  end

  # Rodrigo, 17/10: encaminhar é da pessoa ("mandar ao meu chefe a cobrança que fiz para a Maria"). O modelo e a
  # campanha vão como texto: a cópia não leva as marcas, então no destino não vira modelo (nem cobrança da Meta).
  describe 'modelo e campanha' do
    it 'encaminha o texto do modelo, sem virar modelo no destino' do
      modelo = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, content: 'Olá, Ana! Seu boleto',
                                additional_attributes: { 'template_params' => { 'name' => 'boleto', 'language' => 'pt_BR' } })

      encaminhar([modelo.id])

      copia = copias_em(destino).sole
      expect(copia.content).to eq('Olá, Ana! Seu boleto')
      expect(copia.additional_attributes.to_h.keys & ConversaCanal::Pele::MARCAS_DE_MODELO).to be_empty
    end

    it 'encaminha a mensagem de campanha' do
      campanha = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, content: 'Promoção',
                                  additional_attributes: { 'campaign_id' => 3 })

      encaminhar([campanha.id])

      expect(copias_em(destino).sole.additional_attributes.to_h).not_to have_key('campaign_id')
    end
  end
end
