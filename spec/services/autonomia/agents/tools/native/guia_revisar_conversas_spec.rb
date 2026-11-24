require 'rails_helper'

# A ferramenta `revisar_conversas` (#3158, B8b): começa a revisão de conversas em lote e para quando a pessoa pede.
RSpec.describe Autonomia::Agents::Tools::Native::GuiaRevisarConversas do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contexto) { Autonomia::Guide::Contexto.new(account: account, user: admin) }
  let(:semana) { { 'de' => '2026-11-17', 'ate' => '2026-11-23' } }

  def chamar(params, quem: contexto)
    described_class.new(agent: nil, operador: quem, params: params).call
  end

  def conversa(quando = '2026-11-20 10:00')
    create(:conversation, account: account, created_at: Time.zone.parse(quando))
  end

  it 'está entre as ferramentas do Guia, só lê e tem descrição curta', :aggregate_failures do
    expect(Autonomia::Guide::Seed::FERRAMENTAS).to include('revisar_conversas')
    expect(Autonomia::Agents::Tools::Registry::DO_GUIA).to include(described_class)
    expect(Autonomia::Agents::Tools::Registry::DE_ATENDIMENTO).not_to include(described_class)
    expect(described_class.escreve?).to be(false)
    expect(described_class.description.length).to be <= 400
  end

  it 'começa: cria a revisão, solta o job e põe o cartão no turno', :aggregate_failures do
    escolhidas = [conversa, conversa]

    expect { chamar(semana.merge('titulo' => 'Revisão da semana')) }.to have_enqueued_job(Autonomia::Guide::RevisaoJob)

    revisao = Autonomia::Guide::Revisao.last
    expect(revisao).to have_attributes(status: 'na_fila', titulo: 'Revisão da semana', limite: 300, user: admin)
    expect(revisao.ids).to eq(escolhidas.map(&:id).reverse)
    expect(contexto.revisao).to eq({ 'id' => revisao.id, 'status' => 'na_fila' })
  end

  it 'avisa quando nenhuma conversa atende ao filtro, sem criar nada', :aggregate_failures do
    expect(chamar(semana)).to include('Nenhuma conversa')
    expect(Autonomia::Guide::Revisao.count).to eq(0)
  end

  it 'não começa outra enquanto uma anda' do
    conversa
    chamar(semana)

    expect { chamar(semana) }.not_to change(Autonomia::Guide::Revisao, :count)
  end

  it 'para a revisão em andamento de quem pede', :aggregate_failures do
    conversa
    chamar(semana)

    expect(chamar({ 'acao' => 'parar' })).to include('Parei')
    expect(Autonomia::Guide::Revisao.last.status).to eq('parada')
    expect(chamar({ 'acao' => 'parar' })).to include('Não há revisão')
  end

  it 'devolve a recusa do filtro ao modelo' do
    expect(chamar({ 'de' => 'semana passada', 'ate' => '2026-11-23' })).to include('AAAA-MM-DD')
  end

  it 'avisa a revisão em andamento na pergunta, e só enquanto ela anda', :aggregate_failures do
    conversa
    chamar(semana)
    expect(Autonomia::Guide::Revisoes::Aviso.bloco(account, admin)).to include('REVISÃO DE CONVERSAS EM ANDAMENTO', 'acao parar')

    chamar({ 'acao' => 'parar' })
    expect(Autonomia::Guide::Revisoes::Aviso.bloco(account, admin)).to eq('')
  end
end
