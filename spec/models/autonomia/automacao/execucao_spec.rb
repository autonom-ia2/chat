require 'rails_helper'

RSpec.describe Autonomia::Automacao::Execucao do
  let(:execucao) { create(:autonomia_automacao_execucao) }

  def outra_igual(estado: 'andando')
    described_class.new(account: execucao.account, automacao: execucao.automacao, versao: execucao.versao,
                        alvo: execucao.alvo, chave_gatilho: execucao.chave_gatilho, estado: estado)
  end

  it 'nasce aberta, sem finalizada_em' do
    expect(execucao).to have_attributes(estado: 'andando', finalizada_em: nil)
  end

  described_class::TERMINAIS.each do |estado|
    it "preenche finalizada_em ao chegar em #{estado}" do
      execucao.update!(estado: estado)

      expect(execucao.reload.finalizada_em).to be_present
    end
  end

  it 'não preenche finalizada_em num estado aberto' do
    described_class::ABERTAS.each do |estado|
      execucao.update!(estado: estado)

      expect(execucao.reload.finalizada_em).to be_nil
    end
  end

  it 'recusa estado fora da lista' do
    expect(outra_igual(estado: 'sumiu')).not_to be_valid
  end

  it 'recusa versão de outra automação e automação de outra conta' do
    alheia = create(:autonomia_automacao_versao)

    expect(outra_igual.tap { |nova| nova.versao = alheia }).not_to be_valid
    expect(outra_igual.tap { |nova| nova.account = alheia.account }).not_to be_valid
  end

  it 'o registro recusa execução de outra conta' do
    alheia = create(:autonomia_automacao_execucao)

    expect(build(:autonomia_automacao_registro, execucao: alheia, automacao: execucao.automacao, account: execucao.account)).not_to be_valid
  end

  describe 'uma só aberta por automação, alvo e gatilho (F2.5)' do
    it 'o banco recusa a segunda igual enquanto a primeira está aberta' do
      expect { outra_igual.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { outra_igual(estado: 'esperando').save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'a mesma chave entra de novo depois que a primeira termina' do
      execucao.update!(estado: 'concluida')

      expect { outra_igual.save! }.to change(described_class, :count).by(1)
    end

    it 'outro gatilho ou outro alvo da mesma automação entram juntos' do
      outro_gatilho = outra_igual.tap { |nova| nova.chave_gatilho = 'conversation_resolved' }
      outro_alvo = outra_igual.tap { |nova| nova.alvo = create(:conversation, account: execucao.account) }

      expect { [outro_gatilho, outro_alvo].each(&:save!) }.to change(described_class, :count).by(2)
    end
  end
end
