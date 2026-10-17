require 'rails_helper'

# #1702 — prévia de link no painel: agendada depois do create, gravada em content_attributes.link_preview.
describe ConversaCanal::PreviaDeLinkJob do
  let(:account) { create(:account) }
  let(:canal) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:caixa) { canal.inbox }
  let(:conversa) { create(:conversation, account: account, inbox: caixa) }
  let(:url) { 'https://exemplo.com.br/seguro' }
  let(:imagem) { 'https://exemplo.com.br/imagens/capa.png' }
  let(:html) { Rails.root.join('spec/fixtures/files/conversa_canal/pagina_com_open_graph.html').read }

  before do
    account.enable_features!('conversa_cara_do_canal')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.com.br').and_return(['93.184.216.34'])
    stub_request(:get, url).to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })
    stub_request(:get, imagem).to_return(status: 200, body: Rails.root.join('spec/assets/avatar.png').read,
                                         headers: { 'Content-Type' => 'image/png' })
    Rails.cache.clear
  end

  after { Redis::Alfred.scan_each(match: 'conversa_canal:previa_de_link:cota:*') { |key| Redis::Alfred.delete(key) } }

  def mensagem(content: "Olha só #{url} e me diz", **atributos)
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: content, **atributos)
  end

  describe 'agendamento depois do create' do
    it 'agenda na fila low a mensagem com endereço' do
      expect { mensagem }.to have_enqueued_job(described_class).on_queue('low')
    end

    it 'não agenda nota privada' do
      expect { mensagem(message_type: :outgoing, private: true) }.not_to have_enqueued_job(described_class)
    end

    it 'não agenda sem endereço no texto' do
      expect { mensagem(content: 'sem link aqui') }.not_to have_enqueued_job(described_class)
    end

    it 'não agenda com a chave desligada' do
      account.disable_features!('conversa_cara_do_canal')

      expect { mensagem }.not_to have_enqueued_job(described_class)
    end

    it 'agenda o texto comum enviado pela Cloud API, que sai com preview_url' do
      expect { mensagem(message_type: :outgoing) }.to have_enqueued_job(described_class)
    end

    it 'não agenda mensagem de modelo: o cliente não viu cartão' do
      extras = { 'template_params' => { 'name' => 'promocao', 'language' => 'pt_BR' } }
      expect { mensagem(message_type: :outgoing, additional_attributes: extras) }.not_to have_enqueued_job(described_class)
    end

    it 'não agenda mensagem de campanha' do
      extras = { 'campaign_id' => 7, 'campaign_template_name' => 'promocao' }
      expect { mensagem(message_type: :outgoing, additional_attributes: extras) }.not_to have_enqueued_job(described_class)
    end

    it 'não agenda a enviada por um provedor que não manda preview_url' do
      canal_360 = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      conversa_360 = create(:conversation, account: account, inbox: canal_360.inbox)

      expect do
        create(:message, account: account, inbox: canal_360.inbox, conversation: conversa_360, message_type: :outgoing, content: url)
      end.not_to have_enqueued_job(described_class)
    end

    it 'agenda a recebida em qualquer caixa de WhatsApp' do
      canal_360 = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      conversa_360 = create(:conversation, account: account, inbox: canal_360.inbox)

      expect do
        create(:message, account: account, inbox: canal_360.inbox, conversation: conversa_360, message_type: :incoming, content: url)
      end.to have_enqueued_job(described_class)
    end

    it 'não agenda fora do WhatsApp' do
      outra = create(:inbox, account: account)
      conversa_fora = create(:conversation, account: account, inbox: outra)

      expect do
        create(:message, account: account, inbox: outra, conversation: conversa_fora, message_type: :incoming, content: url)
      end.not_to have_enqueued_job(described_class)
    end
  end

  describe '#perform' do
    it 'grava título, descrição, site e a cópia da imagem no nosso servidor' do
      m = mensagem

      described_class.perform_now(m.id)

      previa = m.reload.content_attributes['link_preview']
      expect(previa).to include('url' => url, 'title' => 'Seguro auto em 5 minutos', 'description' => 'Cotação online, sem ligação.',
                                'site_name' => 'Exemplo Seguros')
      expect(previa['image_url']).to start_with('/rails/active_storage/')
      expect(previa).not_to have_key('image_source')
      expect(m.previa_de_link_imagem).to be_attached
      expect(m.previa_de_link_imagem.content_type).to eq('image/png')
    end

    it 'dispara o message.updated' do
      m = mensagem
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      described_class.perform_now(m.id)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_UPDATED, any_args)
    end

    it 'não guarda imagem que não é foto pelo conteúdo (SVG anunciado como PNG)' do
      stub_request(:get, imagem).to_return(status: 200, body: '<svg xmlns="http://www.w3.org/2000/svg"><script>1</script></svg>',
                                           headers: { 'Content-Type' => 'image/png' })
      m = mensagem

      described_class.perform_now(m.id)

      expect(m.reload.content_attributes['link_preview']).not_to have_key('image_url')
      expect(m.previa_de_link_imagem).not_to be_attached
    end

    it 'usa o cache por endereço: a mesma página não é lida duas vezes' do
      with_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(with_cache)

      described_class.perform_now(mensagem.id)
      described_class.perform_now(mensagem.id)

      expect(a_request(:get, url)).to have_been_made.once
    end

    it 'passada a cota da conta no minuto, a mensagem fica sem prévia e a página não é lida' do
      stub_const("#{described_class}::COTA", 1)
      described_class.perform_now(mensagem.id)
      outra = 'https://exemplo.com.br/outra'
      stub_request(:get, outra).to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })
      m = mensagem(content: "veja #{outra}")

      described_class.perform_now(m.id)

      expect(m.reload.content_attributes).not_to have_key('link_preview')
      expect(a_request(:get, outra)).not_to have_been_made
    end

    it 'falha do site = mensagem sem prévia, sem erro e sem cache da falha' do
      with_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(with_cache)
      stub_request(:get, url).to_timeout
      m = mensagem

      expect { described_class.perform_now(m.id) }.not_to raise_error
      expect(m.reload.content_attributes).not_to have_key('link_preview')
      expect(with_cache.read("conversa_canal:previa_de_link:#{Digest::SHA256.hexdigest(url)}")).to be_nil
    end

    it 'endereço que resolve para IP privado = sem prévia e sem pedido' do
      allow(Resolv).to receive(:getaddresses).with('exemplo.com.br').and_return(['169.254.169.254'])
      m = mensagem

      described_class.perform_now(m.id)

      expect(m.reload.content_attributes).not_to have_key('link_preview')
      expect(a_request(:get, url)).not_to have_been_made
    end

    it 'não busca se a chave foi desligada depois do agendamento' do
      m = mensagem
      account.disable_features!('conversa_cara_do_canal')

      described_class.perform_now(m.id)

      expect(a_request(:get, url)).not_to have_been_made
    end
  end
end
