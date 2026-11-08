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

  # #2679: o texto da IA é cópia de conversa e só vale enquanto a execução anda.
  describe 'os textos da IA' do
    before { execucao.guardar_texto!('p1', 'Oi Ana') }

    it 'guarda pelo id do passo, sem mexer no resto' do
      expect(execucao.reload).to have_attributes(textos: { 'p1' => 'Oi Ana' }, estado: 'andando')
    end

    described_class::TERMINAIS.each do |estado|
      it "somem ao chegar em #{estado}" do
        execucao.update!(estado: estado)

        expect(execucao.reload.textos).to eq({})
      end
    end

    it 'somem quando a rodada termina sem callback (gravar_na_rodada)' do
      execucao.update!(travada_em: Time.current)

      described_class.gravar_na_rodada(execucao.id, execucao.travada_em, estado: 'concluida', cursor: nil)

      expect(execucao.reload.textos).to eq({})
    end

    it 'ficam quando a rodada só espera' do
      execucao.update!(travada_em: Time.current)

      described_class.gravar_na_rodada(execucao.id, execucao.travada_em, estado: 'esperando', cursor: 'p2')

      expect(execucao.reload.textos).to eq('p1' => 'Oi Ana')
    end

    it 'quem fechou enquanto a IA respondia vence: o texto não volta para a execução terminada', :aggregate_failures do
      execucao.automacao.desligar!

      expect(execucao.guardar_texto!('p2', 'Tarde demais')).to be(false)
      expect(execucao.reload.textos).to eq({})
    end

    it 'junta no banco, sem regravar o que outro passo guardou' do
      described_class.find(execucao.id).guardar_texto!('p2', 'Resumo')
      execucao.guardar_texto!('p3', 'Outro')

      expect(execucao.reload.textos).to eq('p1' => 'Oi Ana', 'p2' => 'Resumo', 'p3' => 'Outro')
    end

    it 'somem quando a automação é desligada' do
      execucao.automacao.desligar!

      expect(execucao.reload).to have_attributes(estado: 'parada', textos: {})
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

  it 'recusa alvo de outra conta' do
    expect(outra_igual.tap { |nova| nova.alvo = create(:conversation) }).not_to be_valid
  end

  it 'o banco recusa estado terminal sem finalizada_em e finalizada_em em estado aberto' do
    # Cada tentativa num savepoint: o erro do banco aborta a transação do exemplo. update_all de propósito: é o caminho
    # que pula o callback.
    linha = described_class.where(id: execucao.id)
    gravar = lambda do |campos|
      described_class.transaction(requires_new: true) { linha.update_all(campos) } # rubocop:disable Rails/SkipsModelValidations
    end
    pelo_check = ->(erro) { expect(erro.cause).to be_a(PG::CheckViolation) }

    expect { gravar.call(estado: 'concluida') }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check)
    expect { gravar.call(finalizada_em: Time.current) }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check)
    expect { gravar.call(estado: 'concluida', finalizada_em: Time.current) }.to change { linha.pick(:estado) }.to('concluida')
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
