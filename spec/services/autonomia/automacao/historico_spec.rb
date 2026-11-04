require 'rails_helper'

# "O que aconteceu" (#2498): execuções da mais nova para a mais velha, os passos em ordem, o motivo traduzido, só as
# chaves de `dados` que a tela sabe dizer, e conversa fora da caixa de quem vê sem nome nem ids.
RSpec.describe Autonomia::Automacao::Historico do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:automacao) { create(:autonomia_automacao, account: account) }
  let(:versao) { create(:autonomia_automacao_versao, automacao: automacao) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato) }

  def execucao(chave, alvo: conversa, **atributos)
    create(:autonomia_automacao_execucao, versao: versao, alvo: alvo, chave_gatilho: chave, **atributos)
  end

  def historico(usuario = admin, pagina: 1)
    described_class.new(automacao: automacao, usuario: usuario, pagina: pagina).resultado
  end

  it 'devolve a mais nova primeiro, com os passos em ordem e o motivo em frase', :aggregate_failures do
    velha = travel_to(2.hours.ago) { execucao('a', estado: 'concluida') }
    nova = execucao('b', estado: 'parada')
    create(:autonomia_automacao_registro, execucao: nova, passo: 'p1', resultado: 'ok', dados: { 'ramo' => 'senao' })
    create(:autonomia_automacao_registro, execucao: nova, passo: 'p2', resultado: 'pulado', motivo: 'spam')

    resultado = historico

    expect(resultado[:execucoes].pluck(:id)).to eq([nova.id, velha.id])
    passos = resultado[:execucoes].first[:passos]
    expect(passos.pluck(:passo)).to eq(%w[p1 p2])
    expect(passos.first[:dados]).to eq('ramo' => 'senao')
    expect(passos.last[:motivo]).to eq(I18n.t('autonomia.automacao.motivos.spam'))
    expect(resultado[:execucoes].first[:alvo]).to eq(tipo: 'conversa', visivel: true, conversa_id: conversa.display_id, nome: 'Maria')
  end

  it 'leva a receita de cada versão uma vez só' do
    execucao('a', estado: 'concluida')
    execucao('b', estado: 'concluida')

    expect(historico[:versoes]).to eq(versao.id => { numero: versao.numero, receita: versao.receita })
  end

  it 'repassa só as chaves que a tela sabe dizer' do
    registro = create(:autonomia_automacao_registro, execucao: execucao('a'),
                                                     dados: { 'mensagem_id' => 9, 'ia' => { 'custo_usd' => 0.002 },
                                                              'erro' => 'NoMethodError', 'caderno_id' => 4 })

    expect(historico[:execucoes].first[:passos].first[:dados]).to eq('mensagem_id' => 9, 'ia' => { 'custo_usd' => 0.002 })
    expect(registro.reload.dados).to include('erro')
  end

  it 'dentro de ia, repassa só os números do custo' do
    create(:autonomia_automacao_registro, execucao: execucao('a'),
                                          dados: { 'ia' => { 'custo_usd' => 0.002, 'modelo' => 'm', 'razao' => 'o cliente disse' } })

    expect(historico[:execucoes].first[:passos].first[:dados]).to eq('ia' => { 'custo_usd' => 0.002, 'modelo' => 'm' })
  end

  it 'tira o ia que não vem no formato de custo' do
    create(:autonomia_automacao_registro, execucao: execucao('a'), dados: { 'ia' => 'texto solto', 'ramo' => 'entao' })

    expect(historico[:execucoes].first[:passos].first[:dados]).to eq('ramo' => 'entao')
  end

  it 'serializa a receita pelo mesmo caminho do show e do index' do
    execucao('a')
    allow_any_instance_of(Autonomia::Automacao::Versao).to receive(:receita_para_tela).and_return('mascarada' => true) # rubocop:disable RSpec/AnyInstance

    expect(historico[:versoes].values.first[:receita]).to eq('mascarada' => true)
  end

  it 'mostra só os últimos 30 dias, como a tela diz' do
    travel_to(31.days.ago) { execucao('velha', estado: 'concluida') }
    recente = travel_to(29.days.ago) { execucao('recente', estado: 'concluida') }

    expect(historico[:execucoes].pluck(:id)).to eq([recente.id])
  end

  it 'esconde o nome e os ids da conversa de uma caixa que a pessoa não vê', :aggregate_failures do
    agente = create(:user, account: account, role: :agent)
    create(:autonomia_automacao_registro, execucao: execucao('a'), dados: { 'mensagem_id' => 9, 'ramo' => 'entao' })

    alvo = historico(agente)[:execucoes].first

    expect(alvo[:alvo]).to eq(tipo: 'conversa', visivel: false)
    expect(alvo[:passos].first[:dados]).to eq('ramo' => 'entao')
  end

  it 'mostra a conversa ao agente que é da caixa' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: inbox)
    execucao('a')

    expect(historico(agente)[:execucoes].first[:alvo]).to include(visivel: true, nome: 'Maria')
  end

  it 'pagina de 20 em 20 e diz se há mais', :aggregate_failures do
    21.times { |n| execucao("c#{n}", estado: 'concluida') }

    primeira = historico
    segunda = historico(pagina: 2)

    expect(primeira[:execucoes].size).to eq(20)
    expect(primeira[:mais]).to be(true)
    expect(segunda[:execucoes].size).to eq(1)
    expect(segunda[:mais]).to be(false)
    expect(primeira[:execucoes].pluck(:id) & segunda[:execucoes].pluck(:id)).to be_empty
  end

  it 'diz até quando a execução espera' do
    ate = 2.hours.from_now
    execucao('a', estado: 'esperando', due_at: ate)

    expect(historico[:execucoes].first[:esperando_ate]).to be_within(1.second).of(ate)
  end

  describe '.semana' do
    it 'conta numa consulta só as execuções dos últimos 7 dias, e as que pararam', :aggregate_failures do
      outra = create(:autonomia_automacao, account: account)
      execucao('a', estado: 'concluida')
      execucao('b', estado: 'falhou')
      execucao('c', estado: 'parada')
      travel_to(8.days.ago) { execucao('d', estado: 'concluida') }

      semana = described_class.semana([automacao.id, outra.id])

      expect(semana[automacao.id]).to eq(rodou: 3, parou: 2)
      expect(semana[outra.id]).to eq(rodou: 0, parou: 0)
    end
  end
end
