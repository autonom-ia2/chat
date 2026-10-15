require 'rails_helper'

# Tema 14 (#1434): o escritor único do vínculo, quando o ajudante entra no turno e quantas rodadas o principal ganha.
RSpec.describe Autonomia::Agents::Ajudantes do
  let(:conta) { conta_da_fase2 }
  let(:joana) { criar_principal(conta) }
  let(:clara) { criar_principal(conta, nome: 'Clara') }
  let(:ajudante) { criar_ajudante(conta) }

  describe '.definir!' do
    it 'liga o ajudante a vários principais com um "quando chamar" só' do
      described_class.definir!(ajudante: ajudante, principal_ids: [joana.id, clara.id], quando: 'Dúvida do produto Auto')

      vinculos = Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)
      expect(vinculos.map(&:autonomia_agent_id)).to contain_exactly(joana.id, clara.id)
      expect(vinculos.map(&:description).uniq).to eq(['Dúvida do produto Auto'])
    end

    it 'troca o conjunto inteiro: quem saiu da lista perde o vínculo' do
      described_class.definir!(ajudante: ajudante, principal_ids: [joana.id, clara.id], quando: 'x')

      described_class.definir!(ajudante: ajudante, principal_ids: [clara.id], quando: 'y')

      vinculos = Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)
      expect(vinculos.map(&:autonomia_agent_id)).to eq([clara.id])
      expect(vinculos.first.description).to eq('y')
    end

    it 'exige ao menos um principal: dizer quem ele ajuda é obrigatório' do
      expect { described_class.definir!(ajudante: ajudante, principal_ids: [], quando: 'x') }
        .to raise_error(described_class::Recusado)
    end

    it 'recusa principal de outra conta, sem gravar nada' do
      de_fora = criar_principal(conta_da_fase2)

      expect { described_class.definir!(ajudante: ajudante, principal_ids: [joana.id, de_fora.id], quando: 'x') }
        .to raise_error(described_class::Recusado)
      expect(Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)).to be_empty
    end

    it 'recusa um Copiloto da equipe já existente (sem a marca de origem), sem gravar nada' do
      copiloto = criar_copiloto(conta)

      expect { described_class.definir!(ajudante: copiloto, principal_ids: [joana.id], quando: 'x') }
        .to raise_error(described_class::Recusado, I18n.t('autonomia.agents.ajudante.sem_marca'))
      expect(Autonomia::Agents::Specialist.where(delegate_agent_id: copiloto.id)).to be_empty
    end

    it 'na execução, um vínculo forjado com um Copiloto (sem a marca) não entra no turno' do
      copiloto = criar_copiloto(conta)
      forjado = Autonomia::Agents::Specialist.new(agent: joana, account: conta, delegate: copiloto, name: 'Ana', slug: 'ana',
                                                  description: 'sempre', instruction: '')
      forjado.save(validate: false)

      expect(described_class.disponivel?(forjado.reload)).to be(false)
    end

    it 'recusa ajudante que não é interno' do
      expect { described_class.definir!(ajudante: clara, principal_ids: [joana.id], quando: 'x') }
        .to raise_error(described_class::Recusado)
    end

    it 'dois ajudantes com o mesmo nome no mesmo principal ganham funções diferentes' do
      outro = criar_ajudante(conta)
      described_class.definir!(ajudante: ajudante, principal_ids: [joana.id], quando: 'x')
      described_class.definir!(ajudante: outro, principal_ids: [joana.id], quando: 'y')

      nomes = joana.specialists.map(&:function_name)
      expect(nomes.uniq.size).to eq(2)
    end
  end

  describe '.disponivel?' do
    it 'só com a Fase 2 ligada, ajudante ligado, interno e da mesma conta' do
      vinculo = vincular(joana, ajudante)
      expect(described_class.disponivel?(vinculo)).to be(true)

      ajudante.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.disponivel?(vinculo.reload)).to be(false)
    end

    it 'com a Fase 2 desligada, o vínculo não existe para o turno' do
      conta.update!(internal_attributes: conta.internal_attributes.merge('autonomia_agents_fase2' => false))

      expect(described_class.disponivel?(vincular(joana, ajudante))).to be(false)
    end

    it 'vínculo forjado entre contas (fora do escritor único) não entra no turno: vale a conta do principal' do
      outra = conta_da_fase2
      de_fora = criar_ajudante(outra)
      forjado = Autonomia::Agents::Specialist.new(agent: joana, account: outra, delegate: de_fora, name: 'X', slug: 'x',
                                                  description: 'sempre', instruction: '')
      forjado.save(validate: false)

      expect(described_class.disponivel?(forjado.reload)).to be(false)
      expect(described_class.rodadas(joana)).to be_nil
    end

    it 'aceita só ids inteiros: texto ou objeto recusa, sem gravar' do
      expect { described_class.definir!(ajudante: ajudante, principal_ids: ['abc'], quando: 'x') }
        .to raise_error(described_class::Recusado)
      expect { described_class.definir!(ajudante: ajudante, principal_ids: [{ 'id' => joana.id }], quando: 'x') }
        .to raise_error(described_class::Recusado)
      expect(Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)).to be_empty
    end

    it 'ajudante apagado não é consultado' do
      vinculo = vincular(joana, ajudante)
      ajudante.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.disponivel?(vinculo.reload)).to be(false)
    end
  end

  describe '.rodadas' do
    it 'o principal com ajudante disponível ganha 6 rodadas e 15 minutos' do
      vincular(joana, ajudante)

      expect(described_class.rodadas(joana)).to eq(max_rodadas: 6, max_segundos: 900)
    end

    it 'sem ajudante, ou com a Fase 2 desligada, nada muda (nil: vale o padrão de quem chama)' do
      expect(described_class.rodadas(clara)).to be_nil

      vincular(joana, ajudante)
      conta.update!(internal_attributes: conta.internal_attributes.merge('autonomia_agents_fase2' => false))
      expect(described_class.rodadas(joana.reload)).to be_nil
    end
  end

  describe 'as superfícies usam as rodadas do principal com ajudante' do
    def kwargs_do_answerer
      recebido = nil
      allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
        recebido = kwargs
        original.call(**kwargs)
      end
      allow_any_instance_of(Autonomia::Agents::Answerer).to receive(:answer).and_return(nil) # rubocop:disable RSpec/AnyInstance
      yield
      recebido
    end

    before { vincular(joana, ajudante) }

    it 'o Testar' do
      kwargs = kwargs_do_answerer { Autonomia::Agents::Playground.new(agent: joana, message: 'oi').run }

      expect(kwargs.slice(:max_rodadas, :max_segundos)).to eq(max_rodadas: 6, max_segundos: 900)
    end

    it 'o Copiloto do principal' do
      kwargs = kwargs_do_answerer { Autonomia::Agents::Copilot.new(agent: joana, message: 'oi').suggest }

      expect(kwargs.slice(:max_rodadas, :max_segundos)).to eq(max_rodadas: 6, max_segundos: 900)
    end

    it 'o Testar de quem não tem ajudante segue igual' do
      kwargs = kwargs_do_answerer { Autonomia::Agents::Playground.new(agent: clara, message: 'oi').run }

      expect(kwargs).not_to have_key(:max_rodadas)
    end
  end

  describe 'o atendimento (Responder)' do
    let(:inbox) { create(:inbox, account: conta) }
    let(:conversation) { create(:conversation, account: conta, inbox: inbox, assignee: nil) }

    around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

    it 'o principal com ajudante responde com 6 rodadas e 15 minutos' do
      vincular(joana, ajudante)
      create(:message, account: conta, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi')
      agent_inbox = Autonomia::Agents::AgentInbox.create!(agent: joana, inbox: inbox, account: conta,
                                                          agent_bot: create(:agent_bot, account: conta))
      recebido = nil
      allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
        recebido = kwargs.slice(:max_rodadas, :max_segundos)
        original.call(**kwargs)
      end
      allow_any_instance_of(Autonomia::Agents::Answerer).to receive(:answer).and_return(nil) # rubocop:disable RSpec/AnyInstance

      Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox,
                                                reply_to_message_id: conversation.messages.incoming.last.id).perform

      expect(recebido).to eq(max_rodadas: 6, max_segundos: 900)
    end
  end

  describe 'a lista do Copiloto da conversa' do
    it 'o ajudante vinculado sai da lista de copilotos; o copiloto sem vínculo continua' do
      copiloto = criar_copiloto(conta, nome: 'Ana Copiloto')
      vincular(joana, ajudante)

      lista = Autonomia::Agents::Agent.kept.where(account: conta).copilotos_da_equipe

      expect(lista).to include(copiloto)
      expect(lista).not_to include(ajudante)
    end
  end
end
