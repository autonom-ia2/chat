require 'rails_helper'

# #1479 / #2723 — o agente sabe, em TEXTO, o endereço e o telefone do atendimento (os do agente e os endereços dos locais
# presenciais da página de agendamento), só com a Fase 2 e a flag `agentes_enviar_local_e_contato`. O cartão de contato
# leva o telefone do AGENTE primeiro, depois o da página; o agente sem página mas com telefone ganha `enviar_contato`.
# O endereço do agente não vira mapa. A Lia fica fora.
RSpec.describe Autonomia::Agents::Tools::Native::EnderecoETelefone do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
  let(:host) { create(:user, account: account, role: :agent) }
  let(:centro) { { 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100 - Centro, São Paulo' } }
  let(:pagina) do
    create_booking_profile(account: account, host: host, title: 'Clínica Sorriso',
                           locations: [{ 'type' => 'whatsapp_video' }, centro], contact_phone: '+551140000473')
  end
  let(:dados) { { 'endereco' => 'Av. Brasil, 50 - Campinas', 'telefone' => '+5511940001234' } }
  let(:agent) { criar_principal(account, config: { 'with_knowledge' => false, 'atendimento' => dados }) }
  let(:com_pagina) do
    criar_principal(account, nome: 'Bia', config: { 'with_knowledge' => false, 'atendimento' => dados, 'booking_page_id' => pagina.id })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 77) }
  let(:contato) { Autonomia::Agents::Tools::Native::EnviarContato }
  let(:localizacao) { Autonomia::Agents::Tools::Native::EnviarLocalizacao }

  def instrucoes(agente)
    Autonomia::Agents::PromptBuilder.new(agent: agente.reload, query: 'Onde fica?').instructions
  end

  def chamar_contato(agente)
    contato.new(agent: agente.reload, params: {}, delivery: delivery).call
  end

  describe 'a instrução' do
    it 'traz o endereço e o telefone do agente, em texto' do
      texto = described_class.instrucao(agent)

      expect(texto).to include('# Endereço e telefone', dados['endereco'], dados['telefone'])
      expect(instrucoes(agent)).to include(texto)
    end

    it 'traz o endereço dos locais presenciais da página, sem precisar de coordenada' do
      texto = described_class.instrucao(com_pagina)

      expect(texto).to include('Unidade Centro', centro['address'], dados['endereco'])
      expect(texto).not_to include('whatsapp_video')
    end

    it 'só com a página: os locais dela, sem a linha do agente' do
      sem_dados = criar_principal(account, nome: 'Cris', config: { 'with_knowledge' => false, 'booking_page_id' => pagina.id })

      texto = described_class.instrucao(sem_dados)

      expect(texto).to include(centro['address'])
      expect(texto).not_to include('Endereço do atendimento')
    end

    it 'sem a flag: o prompt fica como antes' do
      account.disable_features!('agentes_enviar_local_e_contato')

      expect(described_class.instrucao(com_pagina.reload)).to be_nil
      expect(instrucoes(com_pagina)).not_to include(dados['endereco'], centro['address'])
    end

    it 'sem a Fase 2: nada' do
      Autonomia::Agents::Fase2.desligar!(account)
      expect(described_class.instrucao(agent.reload)).to be_nil
    end

    it 'sem endereço, sem telefone e sem página: nada' do
      vazio = criar_principal(account, nome: 'Dani', config: { 'with_knowledge' => false,
                                                               'atendimento' => { 'endereco' => '', 'telefone' => '' } })
      expect(described_class.instrucao(vazio)).to be_nil
    end

    it 'a Lia fica fora' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Atenda.')
      lia.update_columns(config: lia.config.to_h.merge('atendimento' => dados)) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.instrucao(lia.reload)).to be_nil
    end
  end

  describe 'quem fica fora e os tetos da instrução' do
    it 'agente interno (copiloto) e ajudante ficam fora' do
      copiloto = criar_copiloto(account)
      ajudante = criar_ajudante(account)
      [copiloto, ajudante].each do |agente|
        agente.update!(config: agente.config.merge('atendimento' => dados, 'booking_page_id' => pagina.id))
        expect(described_class.instrucao(agente.reload)).to be_nil
        expect(Autonomia::Agents::Tools::Native::CartaoDaPagina.contato_do_agente(agente)).to be_nil
        expect(Autonomia::Agents::Tools::Native::CartaoDaPagina.slugs_extras(agente)).to be_empty
      end
    end

    it 'agente de sistema fica fora' do
      sistema = criar_principal(account, config: { 'with_knowledge' => false, 'atendimento' => dados })
      sistema.update_columns(config: sistema.config.merge('system_key' => 'guia', 'booking_page_id' => pagina.id)) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.instrucao(sistema.reload)).to be_nil
      expect(Autonomia::Agents::Tools::Native::CartaoDaPagina.contato_do_agente(sistema)).to be_nil
    end

    it 'agente de outra conta apontando para a página desta conta não recebe os locais' do
      outra = conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') }
      estranho = criar_principal(outra, config: { 'with_knowledge' => false, 'atendimento' => dados })
      estranho.update_columns(config: estranho.config.merge('booking_page_id' => pagina.id)) # rubocop:disable Rails/SkipsModelValidations

      texto = described_class.instrucao(estranho.reload)

      expect(texto).to include(dados['endereco'])
      expect(texto).not_to include(centro['address'])
    end

    it 'teto de locais e de tamanho de cada endereço' do
      maximo = Autonomia::Agents::DadosDoAtendimento::MAX_ENDERECO
      muitos = Array.new(described_class::MAX_LOCAIS + 3) do |indice|
        { 'type' => 'in_person', 'label' => "Unidade #{indice}", 'address' => "Rua #{indice}, #{'x' * (maximo + 50)}" }
      end
      pagina.update_column(:locations, muitos) # rubocop:disable Rails/SkipsModelValidations

      texto = described_class.instrucao(com_pagina.reload)

      expect(texto.scan('Unidade ').size).to eq(described_class::MAX_LOCAIS)
      expect(texto).not_to include('x' * (maximo + 1))
    end
  end

  describe 'enviar_contato' do
    it 'o telefone do agente vence o da página, com o título da página como nome' do
      chamar_contato(com_pagina)

      expect(delivery.cartoes.sole['rich_message']).to eq('type' => 'contact', 'name' => 'Clínica Sorriso',
                                                          'phone' => dados['telefone'])
    end

    it 'agente sem telefone: o da página, como antes' do
      com_pagina.update!(config: com_pagina.config.merge('atendimento' => { 'endereco' => '', 'telefone' => '' }))

      chamar_contato(com_pagina)

      expect(delivery.cartoes.sole['rich_message']['phone']).to eq('+551140000473')
    end

    it 'agente sem página mas com telefone ganha só enviar_contato, com o nome da conta' do
      catalogo = Autonomia::Agents::Tools::Registry.for_agent(agent.reload)

      expect(catalogo).to include(contato)
      expect(catalogo).not_to include(localizacao)
      chamar_contato(agent)
      expect(delivery.cartoes.sole['rich_message']).to eq('type' => 'contact', 'name' => account.name,
                                                          'phone' => dados['telefone'])
    end

    it 'agente sem página e sem telefone: sem enviar_contato' do
      vazio = criar_principal(account, nome: 'Eva', config: { 'with_knowledge' => false,
                                                              'atendimento' => { 'endereco' => 'Rua X', 'telefone' => '' } })
      expect(Autonomia::Agents::Tools::Registry.for_agent(vazio)).not_to include(contato, localizacao)
    end

    it 'sem a flag: o telefone do agente não liga nada' do
      account.disable_features!('agentes_enviar_local_e_contato')
      expect(Array(agent.reload.ferramentas_nativas)).not_to include('enviar_contato')
      expect(contato.available_for?(agent)).to be(false)
    end

    it 'com o telefone do agente preenchido e inválido, nunca cai no telefone da página' do
      ['+55 11', '11940001234'].each do |gravado|
        com_pagina.update_columns(config: com_pagina.config.merge('atendimento' => { 'endereco' => '', 'telefone' => gravado })) # rubocop:disable Rails/SkipsModelValidations

        expect(Autonomia::Agents::Tools::Native::CartaoDaPagina.contato_do_agente(com_pagina.reload)).to be_nil
        expect(contato.available_for?(com_pagina)).to be(false)
      end
    end

    it 'com o telefone do agente, não pede coordenada da página' do
      agente = com_pagina.reload # a página nasce antes (o salvar dela pede a coordenada por conta própria)
      allow(Crm::BookingV2::GeocodificarLocaisJob).to receive(:pedir)

      cartao = Autonomia::Agents::Tools::Native::CartaoDaPagina.contato_do_agente(agente)

      expect(cartao).to include('name' => 'Clínica Sorriso', 'phone' => dados['telefone'])
      expect(Crm::BookingV2::GeocodificarLocaisJob).not_to have_received(:pedir)
    end

    it 'o endereço do agente não vira mapa' do
      expect(localizacao.available_for?(agent.reload)).to be(false)
    end

    it 'a Lia fica fora, mesmo com telefone gravado' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Atenda.')
      lia.update_columns(config: lia.config.to_h.merge('atendimento' => dados)) # rubocop:disable Rails/SkipsModelValidations
      expect(Array(lia.reload.ferramentas_nativas)).not_to include('enviar_contato')
      expect(contato.available_for?(lia)).to be(false)
    end
  end

  describe 'a resolução dos pedaços (CartoesDoTurno.resolver)' do
    let(:resolver) { Autonomia::Agents::Operate::CartoesDoTurno }
    let(:referencia) { { 'tipo' => 'contact', 'chave' => Autonomia::Agents::Tools::Native::CartaoDaPagina::CHAVE_DO_CONTATO, 'token' => 't' } }

    it 'segue a mesma ordem: o telefone do agente primeiro' do
      cartoes, perdidos = resolver.resolver([referencia], com_pagina.reload)

      expect(perdidos).to eq(0)
      expect(cartoes.sole['rich_message']['phone']).to eq(dados['telefone'])
    end

    it 'agente sem página: resolve pelo telefone do agente' do
      cartoes, perdidos = resolver.resolver([referencia], agent.reload)

      expect(perdidos).to eq(0)
      expect(cartoes.sole['rich_message']).to include('name' => account.name, 'phone' => dados['telefone'])
    end

    it 'a Lia não resolve cartão' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Atenda.')
      lia.update_columns(config: lia.config.to_h.merge('atendimento' => dados, 'booking_page_id' => pagina.id)) # rubocop:disable Rails/SkipsModelValidations

      expect(resolver.resolver([referencia], lia.reload)).to eq([[], 1])
    end

    it 'o telefone do agente sumiu e não há página: o cartão fica fora' do
      agent.update!(config: agent.config.merge('atendimento' => { 'endereco' => '', 'telefone' => '' }))

      expect(resolver.resolver([referencia], agent.reload)).to eq([[], 1])
    end
  end
end
