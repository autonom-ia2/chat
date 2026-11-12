require 'rails_helper'

# O CI cobra lib/operator_guide/automacao-recursos.yml, a lista de ações que viram passo da Automação livre
# (#2414 F3.2, ADR-001 2.1 e D13).
RSpec.describe Autonomia::Automacao::AcoesPermitidas do
  let(:permitidas) { described_class }
  let(:formatos) { Autonomia::Guide::Formatos.todos }
  let(:recursos_do_catalogo) { formatos.keys.map { |acao| permitidas.recurso_de(acao) }.uniq }

  it 'classifica todo recurso do catálogo do Guia, uma vez só' do
    classificados = permitidas.classificados

    expect(recursos_do_catalogo - classificados).to be_empty
    expect(classificados - recursos_do_catalogo).to be_empty
    expect(classificados.tally.select { |_recurso, vezes| vezes > 1 }).to be_empty
  end

  it 'dá um motivo a cada recurso liberado e a cada grupo de fora' do
    expect(permitidas.lista['passo'].values.pluck('motivo')).to all(be_present)
    expect(permitidas.lista['fora'].pluck('motivo')).to all(be_present)
  end

  it 'só libera ação que existe, no recurso em que está, com formato completo' do
    permitidas.lista['passo'].each do |recurso, bloco|
      bloco['acoes'].each_key do |acao|
        expect(formatos[acao]).to be_present, "#{acao} não existe no catálogo"
        expect(permitidas.recurso_de(acao)).to eq(recurso), "#{acao} não é de #{recurso}"
        expect(formatos[acao]['completo']).to be(true), "#{acao} tem formato incompleto"
      end
    end
  end

  it 'não libera ação sem desfazer nem ação que só se faz na tela' do
    liberadas = permitidas.acoes.keys

    expect(liberadas & Autonomia::Guide::Acoes::SEM_DESFAZER).to be_empty
    expect(liberadas.select { |acao| Autonomia::Guide::Acoes.fora_do_catalogo?(acao) }).to be_empty
  end

  it 'nenhum DELETE vira passo, de recurso nenhum' do
    expect(permitidas.acoes.keys.select { |acao| acao.start_with?('DELETE ') }).to be_empty
  end

  it 'nunca libera apagar funil, etapa, caixa, agente, etiqueta ou atributo (F3.11)' do
    apagar_estrutura = formatos.keys.select do |acao|
      acao.start_with?('DELETE ') && permitidas::ESTRUTURA.include?(permitidas.recurso_de(acao))
    end

    expect(apagar_estrutura).to include('DELETE labels/:id', 'DELETE crm/stages/:id', 'DELETE inboxes/:id')
    expect(apagar_estrutura.select { |acao| permitidas.permitida?(acao) }).to be_empty
  end

  it 'deixa fora usuários, funções, conta, integrações, webhooks, tokens e as IAs (ADR-001 2.1)' do
    expect(permitidas.sempre_fora).to include('agents', 'custom_roles', 'api/v1/accounts', 'webhooks', 'integrations/slack',
                                              'whatsapp/authorizations', 'crm/integration_tokens', 'crm/ai_settings',
                                              'crm/ai_suggestions')
    expect(permitidas.lista['passo'].keys & permitidas.sempre_fora).to be_empty
    expect(permitidas.permitida?('DELETE agents/:id')).to be(false)
  end

  it 'só exige, fixa ou proíbe campo que a ação aceita' do
    permitidas.acoes.each do |acao, opcoes|
      campos = Array(opcoes['exige']) + opcoes.fetch('fixos', {}).keys + Array(opcoes['proibe']).map { |campo| campo.split('.').first }
      expect(campos - formatos[acao].fetch('campos', {}).keys).to be_empty, acao
    end
  end

  it 'pede descrição ao criar etiqueta e atributo (F3.10)' do
    expect(permitidas.exige('POST labels')).to eq(['description'])
    expect(permitidas.exige('POST custom_attribute_definitions')).to eq(['attribute_description'])
  end

  # #2633: a pergunta única de "ação de funil", do salvar e do motor; o recurso sai da lista.
  it 'de_funil? só nas ações permitidas de recurso crm/', :aggregate_failures do
    expect(permitidas.de_funil?('PATCH crm/cards/:id')).to be(true)
    expect(permitidas.de_funil?('POST conversations/:id/toggle_priority')).to be(false)
    expect(permitidas.de_funil?('DELETE crm/pipelines/:id')).to be(false)
  end

  describe '#2660 lote A: retorno e agenda' do
    it 'mexe no retorno que já existe; criar continua só pelo passo nativo (D2)', :aggregate_failures do
      expect(%w[complete cancel reschedule dismiss_reminder].map { |gesto| permitidas.permitida?("POST crm/follow_ups/:id/#{gesto}") })
        .to all(be(true))
      expect(permitidas.permitida?('POST crm/follow_ups')).to be(false)
      expect(permitidas.de_funil?('POST crm/follow_ups/:id/complete')).to be(true)
    end

    it 'não troca o modo nem o texto do envio automático pela rota crua', :aggregate_failures do
      expect(permitidas.proibidos('PATCH crm/follow_ups/:id', { 'automation_mode' => 'auto_send_message' })).to eq(['automation_mode'])
      expect(permitidas.proibidos('PUT crm/follow_ups/:id', { 'metadata' => { 'message_body' => 'Oi' } })).to eq(['metadata'])
      expect(permitidas.proibidos('PATCH crm/follow_ups/:id', { 'title' => 'Ligar de novo', 'due_at' => '2026-12-01T10:00:00Z' }))
        .to be_empty
    end

    it 'na reunião, só registra se aconteceu', :aggregate_failures do
      expect(permitidas.permitida?('POST crm/meetings/:id/record_outcome')).to be(true)
      expect(['POST crm/meetings', 'PATCH crm/meetings/:id', 'POST crm/meetings/:id/sync'].map { |acao| permitidas.permitida?(acao) })
        .to all(be(false))
    end

    it 'na página de agendamento, deixa fora o texto ao cliente, passar reuniões e apagar', :aggregate_failures do
      expect(permitidas.proibidos('PATCH crm/booking_pages/:id', { 'booking_page' => { 'notice_texts' => {} } }))
        .to eq(['booking_page.notice_texts'])
      expect(permitidas.proibidos('PUT crm/booking_pages/:id', { 'invite_text' => 'Agende aqui' })).to eq(['invite_text'])
      expect(permitidas.permitida?('POST crm/booking_pages/:id/publish')).to be(true)
      expect(permitidas.permitida?('POST crm/booking_pages/reassign')).to be(false)
      expect(permitidas.permitida?('DELETE crm/booking_pages/:id')).to be(false)
    end

    it 'gera o link de agendamento sem mandar' do
      expect([permitidas.permitida?('POST crm/booking_invites'), permitidas.permitida?('POST crm/booking_invites/:id/deliver')])
        .to eq([true, false])
    end
  end
end
