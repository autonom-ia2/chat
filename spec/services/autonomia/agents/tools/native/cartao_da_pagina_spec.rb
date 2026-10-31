require 'rails_helper'

# #1479 F3: `enviar_localizacao` e `enviar_contato`. Entram sozinhas no catálogo do agente que tem página de
# agendamento, com a Fase 2 e a flag `agentes_enviar_local_e_contato`, e só quando a página tem o dado (local presencial
# com coordenada, telefone de contato válido). Não mandam nada na hora: marcam o cartão no contexto do turno, e o
# Responder o manda depois do texto.
RSpec.describe Autonomia::Agents::Tools::Native::CartaoDaPagina do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
  let(:host) { create(:user, account: account, role: :agent) }
  let(:centro) { { 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100 - Centro, São Paulo' } }
  let(:paulista) { { 'type' => 'in_person', 'label' => 'Unidade Paulista', 'address' => 'Av. Paulista, 1000 - São Paulo' } }
  let(:pagina) do
    create_booking_profile(account: account, host: host, title: 'Clínica Sorriso',
                           locations: [{ 'type' => 'whatsapp_video' }, centro], contact_phone: '+551140000473')
  end
  let(:agent) { criar_principal(account, config: { 'with_knowledge' => false, 'booking_page_id' => pagina.id }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 77) }
  let(:localizacao) { Autonomia::Agents::Tools::Native::EnviarLocalizacao }
  let(:contato) { Autonomia::Agents::Tools::Native::EnviarContato }

  # As coordenadas são do servidor (o job as grava sem callbacks): o teste as põe do mesmo jeito.
  def com_coordenadas(enderecos)
    lista = pagina.reload.locations.map do |item|
      ponto = enderecos[item['address']]
      ponto ? item.merge('latitude' => ponto[0], 'longitude' => ponto[1]) : item
    end
    pagina.update_column(:locations, lista) # rubocop:disable Rails/SkipsModelValidations
  end

  def catalogo(agente = agent)
    Autonomia::Agents::Tools::Registry.for_agent(agente.reload)
  end

  def chamar(ferramenta, params = {}, entrega: delivery)
    ferramenta.new(agent: agent.reload, params: params, delivery: entrega).call
  end

  describe 'catálogo' do
    before { com_coordenadas(centro['address'] => [-23.5489, -46.6388]) }

    it 'oferece as duas com a Fase 2, a flag, a página e o dado' do
      expect(catalogo).to include(localizacao, contato)
    end

    it 'sem a flag: nenhuma das duas' do
      account.disable_features!('agentes_enviar_local_e_contato')
      expect(catalogo).not_to include(localizacao, contato)
      expect(agent.reload.ferramentas_nativas).not_to include('enviar_localizacao', 'enviar_contato')
    end

    it 'sem a Fase 2: nenhuma das duas' do
      Autonomia::Agents::Fase2.desligar!(account)
      expect(catalogo).not_to include(localizacao, contato)
    end

    it 'sem página escolhida: nenhuma das duas' do
      agent.update!(config: agent.config.merge('booking_page_id' => nil))
      expect(catalogo).not_to include(localizacao, contato)
    end

    it 'local sem coordenada: sem o mapa, com o contato' do
      pagina.update_column(:locations, [centro]) # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(localizacao)
      expect(catalogo).to include(contato)
    end

    context 'when the page predates the flag (address without coordinate)' do
      include ActiveJob::TestHelper

      let(:busca) { instance_double(Crm::BookingV2::GeocodificarLocaisJob::Busca) }
      let(:lugar) { { latitude: -23.5489, longitude: -46.6388, tipos: %w[street_address], tipo_principal: nil } }

      def limpar_redis
        Redis::Alfred.scan_each(match: 'crm:booking_v2:geocodificar:*') { |chave| Redis::Alfred.delete(chave) }
      end

      before do
        limpar_redis
        pagina.update_column(:locations, [centro]) # rubocop:disable Rails/SkipsModelValidations
        clear_enqueued_jobs
        allow(Crm::BookingV2::GeocodificarLocaisJob::Busca).to receive_messages(configurada?: true, para: busca)
        allow(busca).to receive_messages(suggestions: [{ text: centro['address'], place_id: 'ChIJ123' }], details: lugar)
      end

      after { limpar_redis }

      it 'o 1º turno pede a coordenada (uma vez) e o 2º turno já tem enviar_localizacao' do
        expect(catalogo).not_to include(localizacao)
        expect(catalogo).not_to include(localizacao)
        expect(enqueued_jobs.count { |item| item[:job] == Crm::BookingV2::GeocodificarLocaisJob }).to eq(1)

        perform_enqueued_jobs

        expect(catalogo).to include(localizacao)
        expect(busca).to have_received(:suggestions).once
      end
    end

    it 'coordenada fora do mapa ou em texto não conta' do
      com_coordenadas(centro['address'] => [-123.0, -46.6])
      expect(catalogo).not_to include(localizacao)
      com_coordenadas(centro['address'] => ['-23.5', '-46.6'])
      expect(catalogo).not_to include(localizacao)
    end

    it 'local presencial sem endereço não conta, mesmo com coordenada' do
      pagina.update_column(:locations, [{ 'type' => 'in_person', 'latitude' => -23.5, 'longitude' => -46.6 }]) # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(localizacao)
    end

    it 'telefone inválido ou vazio: sem o contato' do
      pagina.update_column(:contact_phone, '1140000473') # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(contato)
      pagina.update_column(:contact_phone, '+55 11') # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(contato)
      pagina.update_column(:contact_phone, nil) # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(contato)
      expect(catalogo).to include(localizacao)
    end

    it 'a Lia fica fora, mesmo com a página gravada' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Atenda.')
      lia.update_columns(config: lia.config.to_h.merge('booking_page_id' => pagina.id)) # rubocop:disable Rails/SkipsModelValidations
      expect(lia.reload.ferramentas_nativas).not_to include('enviar_localizacao', 'enviar_contato')
      expect(localizacao.available_for?(lia)).to be(false)
      expect(contato.available_for?(lia)).to be(false)
    end

    it 'página de outra conta não vale' do
      outra = create(:account)
      estrangeira = create_booking_profile(account: outra, host: create(:user, account: outra, role: :agent), locations: [centro],
                                           contact_phone: '+551140000473')
      agent.update_columns(config: agent.config.merge('booking_page_id' => estrangeira.id)) # rubocop:disable Rails/SkipsModelValidations
      expect(catalogo).not_to include(localizacao, contato)
    end
  end

  describe 'enviar_localizacao' do
    context 'with one local' do
      before { com_coordenadas(centro['address'] => [-23.5489, -46.6388]) }

      it 'sem parâmetro; marca o mapa e devolve o texto curto' do
        expect(localizacao.openai_schema(agent)[:parameters][:properties]).to be_empty

        texto = chamar(localizacao)

        expect(texto).to include('Unidade Centro').and include('não escreva')
        expect(delivery.cartoes.sole).to include(
          'tipo' => 'location',
          'rich_message' => { 'type' => 'location', 'latitude' => -23.5489, 'longitude' => -46.6388, 'name' => 'Unidade Centro',
                              'address' => centro['address'] }
        )
      end

      it 'chamada duas vezes: um cartão só' do
        2.times { chamar(localizacao) }
        expect(delivery.cartoes.size).to eq(1)
      end

      it 'sem contexto de entrega (Testar): erro nomeado, nada marcado' do
        expect(JSON.parse(chamar(localizacao, entrega: nil))).to eq('error' => 'cartao_sem_conversa')
      end

      it 'o cartão sai no formato que o tipo aceita' do
        chamar(localizacao)
        expect(RichMessages::Types::Location.new(delivery.cartoes.sole['rich_message']).error_for('')).to be_nil
      end
    end

    context 'with two locals' do
      before do
        pagina.update_column(:locations, [centro, paulista]) # rubocop:disable Rails/SkipsModelValidations
        com_coordenadas(centro['address'] => [-23.5489, -46.6388], paulista['address'] => [-23.5614, -46.6559])
      end

      let(:ids) { described_class.locais(pagina.reload).pluck('id') }

      it 'local_id obrigatório, com os dois na lista fechada e na descrição' do
        schema = localizacao.openai_schema(agent)
        expect(schema[:parameters][:required]).to eq(['local_id'])
        expect(schema[:parameters][:properties]['local_id']['enum']).to match_array(ids)
        expect(schema[:description]).to include('Unidade Centro', centro['address'], 'Unidade Paulista', paulista['address'])
      end

      it 'marca o local pedido' do
        chamar(localizacao, { 'local_id' => ids.last })
        expect(delivery.cartoes.sole['rich_message']).to include('name' => 'Unidade Paulista', 'latitude' => -23.5614)
      end

      it 'os dois locais: dois cartões' do
        ids.each { |id| chamar(localizacao, { 'local_id' => id }) }
        expect(delivery.cartoes.map { |cartao| cartao['rich_message']['name'] }).to eq(['Unidade Centro', 'Unidade Paulista'])
      end

      it 'local_id inválido ou ausente: recusa com a lista, nada marcado' do
        [{ 'local_id' => 'nao-existe' }, {}].each do |params|
          texto = chamar(localizacao, params)
          expect(texto).to include('Unidade Centro', 'Unidade Paulista', ids.first)
        end
        expect(delivery.cartoes).to be_empty
      end

      it 'o id de um local não muda quando a ordem da lista muda' do
        antes = ids
        pagina.update_column(:locations, pagina.reload.locations.reverse) # rubocop:disable Rails/SkipsModelValidations
        expect(described_class.locais(pagina.reload).pluck('id')).to eq(antes.reverse)
      end
    end

    it 'o dado sumiu entre o catálogo e a chamada: recusa, nada marcado' do
      pagina.update_column(:locations, [centro]) # rubocop:disable Rails/SkipsModelValidations
      expect(chamar(localizacao)).to be_a(String)
      expect(delivery.cartoes).to be_empty
    end
  end

  describe 'enviar_contato' do
    it 'manda só o contact_phone da página, com o título como nome' do
      create(:user, account: account, role: :agent, name: 'Pessoa da equipe')
      texto = chamar(contato)

      expect(texto).to include('não escreva')
      expect(delivery.cartoes.sole).to include(
        'tipo' => 'contact', 'rich_message' => { 'type' => 'contact', 'name' => 'Clínica Sorriso', 'phone' => '+551140000473' }
      )
    end

    it 'telefone com espaço e hífen vira só dígitos depois do +' do
      pagina.update_column(:contact_phone, '+55 (11) 4000-0473') # rubocop:disable Rails/SkipsModelValidations
      chamar(contato)
      expect(delivery.cartoes.sole['rich_message']['phone']).to eq('+551140000473')
    end

    it 'sem título: o nome da conta, até 100 caracteres (nunca o nome de uma pessoa da equipe)' do
      pagina.update_columns(title: nil) # rubocop:disable Rails/SkipsModelValidations
      host.update!(name: 'Pessoa da equipe')
      account.update!(name: 'C' * 150)
      chamar(contato)
      expect(delivery.cartoes.sole['rich_message']['name']).to eq('C' * 100)
    end

    it 'chamada duas vezes: um cartão só' do
      2.times { chamar(contato) }
      expect(delivery.cartoes.size).to eq(1)
    end

    it 'sem contexto de entrega (Testar): erro nomeado' do
      expect(JSON.parse(chamar(contato, entrega: nil))).to eq('error' => 'cartao_sem_conversa')
    end

    it 'o telefone sumiu entre o catálogo e a chamada: recusa, nada marcado' do
      pagina.update_column(:contact_phone, nil) # rubocop:disable Rails/SkipsModelValidations
      expect(chamar(contato)).to be_a(String)
      expect(delivery.cartoes).to be_empty
    end
  end
end
