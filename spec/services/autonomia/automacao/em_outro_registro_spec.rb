require 'rails_helper'

# G18 (#2671): a marca da execução filha e o Roteiro dela.
RSpec.describe Autonomia::Automacao::EmOutroRegistro do
  let(:execucao) { instance_double(Autonomia::Automacao::Execucao, id: 7) }

  it 'marca a filha com a mãe, a base e o id do registro, e devolve o id do passo mesmo com ":"', :aggregate_failures do
    card = Crm::Card.new(id: 42)
    marca = described_class.marca(execucao, card, 'passo:um')

    expect(marca).to eq('em:7:card:42:passo:um')
    expect(described_class.da(instance_double(Autonomia::Automacao::Execucao, evento: marca))).to eq([7, 'passo:um'])
  end

  it 'a execução que não é filha (evento de mensagem, de atividade, nenhum) não tem mãe', :aggregate_failures do
    ['mensagem:9', 'card.ganho:atividade:3', nil].each do |evento|
      expect(described_class.da(instance_double(Autonomia::Automacao::Execucao, evento: evento))).to be_nil
    end
  end

  it 'a filha anda só no ramo do passo: começa no primeiro passo dele e acaba no fim dele', :aggregate_failures do
    receita = { 'passos' => [{ 'id' => 'antes', 'tipo' => 'parar' },
                             { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'passos' => [{ 'id' => 'r1' }, { 'id' => 'r2' }] },
                             { 'id' => 'depois', 'tipo' => 'parar' }] }
    versao = instance_double(Autonomia::Automacao::Versao, receita: receita)
    filha = instance_double(Autonomia::Automacao::Execucao, evento: 'em:7:card:42:outro', versao: versao)
    roteiro = Autonomia::Automacao::Roteiro.da(filha)

    expect(roteiro.primeiro['id']).to eq('r1')
    expect(roteiro.seguinte('r1')['id']).to eq('r2')
    expect(roteiro.seguinte('r2')).to be_nil
  end

  it 'a filha cujo passo sumiu da versão não anda, em vez de rodar a receita da mãe no registro dela' do
    versao = instance_double(Autonomia::Automacao::Versao, receita: { 'passos' => [{ 'id' => 'antes', 'tipo' => 'parar' }] })
    filha = instance_double(Autonomia::Automacao::Execucao, evento: 'em:7:card:42:outro', versao: versao)

    expect(Autonomia::Automacao::Roteiro.da(filha).primeiro).to be_nil
  end

  # G65 (#2842): a filha lê o registro de origem (o alvo da mãe) na hora, com a permissão de quem ligou.
  describe 'origem.* na filha' do
    let(:account) { create(:account) }
    let(:dona) { create(:user, account: account, role: :administrator) }
    let(:joao) { create(:contact, account: account, name: 'João') }
    let(:maria) { create(:contact, account: account, name: 'Maria') }
    let(:versao) { create(:autonomia_automacao_versao, automacao: create(:autonomia_automacao, account: account, ligada_por: dona)) }
    let(:card) do
      funil, etapa = create_crm_pipeline(account: account, user: dona)
      account.crm_cards.create!(pipeline: funil, stage: etapa, contact: joao, title: 'Banho do Rex', currency: 'BRL', value_cents: 15_000)
    end
    let(:mae) { create(:autonomia_automacao_execucao, versao: versao, alvo: card, chave_gatilho: 'card.ganho') }
    let(:filha) do
      create(:autonomia_automacao_execucao, versao: versao, alvo: maria, chave_gatilho: 'card.ganho',
                                            evento: "em:#{mae.id}:contato:#{maria.id}:outro")
    end

    def ler(execucao, caminho, quem: dona)
      contexto = Autonomia::Automacao::Contexto.de(execucao.alvo, execucao: execucao)
      Autonomia::Automacao::Valores.new(alvo: contexto, quem: quem).ler(caminho)
    end

    it 'lê o alvo da mãe e as pontes dele, e o próprio registro segue sendo o da filha', :aggregate_failures do
      expect(ler(filha, 'origem.contato.nome')).to eq('João')
      expect(ler(filha, 'origem.card.titulo')).to eq('Banho do Rex')
      expect(ler(filha, 'contato.nome')).to eq('Maria')
    end

    it 'lê na hora: o que mudou na origem depois de a filha abrir vale' do
      filha
      joao.update!(name: 'João Pedro')

      expect(ler(filha, 'origem.contato.nome')).to eq('João Pedro')
    end

    it 'o valor protegido só com a permissão de quem ligou', :aggregate_failures do
      expect(ler(filha, 'origem.card.valor')).to eq(150)
      expect(ler(filha, 'origem.card.valor', quem: nil)).to be_nil
    end

    it 'fora da filha, origem.* lê vazio' do
      expect(ler(mae, 'origem.contato.nome')).to be_nil
    end
  end

  it 'a filha nunca abre neta: o passo dentro dela é pulado na rodada, sem procurar nada', :aggregate_failures do
    filha = instance_double(Autonomia::Automacao::Execucao, evento: 'em:7:card:42:outro')
    passo = { 'id' => 'neta', 'tipo' => 'em_outro_registro', 'registro' => { 'de' => 'cards_do_contato' }, 'passos' => [] }
    resultado = Autonomia::Automacao::PassoEmOutroRegistro.new(execucao: filha, passo: passo, valores: nil, acesso: nil).executar

    expect(resultado).to have_attributes(tipo: :pulado, motivo: 'receita_com_problema')
    expect(Autonomia::Automacao::EmOutroRegistroJob).not_to have_been_enqueued
  end
end
