require 'rails_helper'

RSpec.describe Onboarding::Progress do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:progresso) { described_class.new(account: account, user: user) }

  def status(passo_id)
    progresso.perform.find { |passo| passo[:id] == passo_id }[:status]
  end

  describe 'conta recém-criada' do
    it 'começa com tudo pendente' do
      expect(progresso.perform.map { |passo| passo[:status] }.uniq).to eq(['pendente'])
    end

    it 'entrega os campos que a tela precisa' do
      primeiro = progresso.perform.first

      expect(primeiro).to include(:id, :ordem, :titulo, :por_que, :rota, :alvo_destaque, :pulavel, :status)
    end
  end

  describe 'custo das consultas' do
    it 'faz no máximo uma consulta por regra, sem varrer tabela' do
      account
      user
      consultas = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, dados|
        consultas << dados[:sql] unless dados[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
      end

      described_class.new(account: account, user: user).perform
      ActiveSupport::Notifications.unsubscribe(assinatura)

      expect(consultas.size).to be <= Onboarding::Progress::REGRAS.size + 4
      expect(consultas).to all(match(/LIMIT|COUNT|EXISTS/i))
    end
  end

  describe 'passo 0, perfil' do
    it 'fica feito quando o usuário tem aviso do navegador ligado' do
      expect(status('perfil')).to eq('pendente')

      create(:notification_subscription, user: user)

      expect(status('perfil')).to eq('feito')
    end
  end

  describe 'passo 1, chave da OpenAI' do
    it 'fica feito quando a credencial de IA resolve' do
      expect(status('chave_ia')).to eq('pendente')

      resolvedor = instance_double(Crm::Ai::CredentialResolver, configured?: true)
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolvedor)

      expect(status('chave_ia')).to eq('feito')
    end
  end

  describe 'passo 2, canal' do
    it 'exige caixa E mensagem recebida' do
      inbox = create(:inbox, account: account)
      expect(status('canal')).to eq('pendente')

      conversa = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, conversation: conversa, message_type: :incoming)

      expect(status('canal')).to eq('feito')
    end
  end

  describe 'passo 3, primeira resposta' do
    let(:conversa) { create(:conversation, account: account, inbox: create(:inbox, account: account)) }

    it 'não conta resposta que não saiu de uma pessoa' do
      create(:message, :bot_message, account: account, conversation: conversa)

      expect(status('primeira_resposta')).to eq('pendente')
    end

    it 'fica feito quando alguém responde pelo painel' do
      create(:message, account: account, conversation: conversa, message_type: :outgoing, sender: user)

      expect(status('primeira_resposta')).to eq('feito')
    end
  end

  describe 'passo 4, funil' do
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil Comercial') }
    let(:etapa) { Crm::PipelineStage.create!(account: account, pipeline: pipeline, name: 'Novo', position: 1) }

    it 'exige caixa ligada ao funil E card' do
      inbox = create(:inbox, account: account)
      Crm::PipelineInbox.create!(account: account, pipeline: pipeline, inbox: inbox)

      expect(status('funil')).to eq('pendente')

      Crm::Card.create!(account: account, pipeline: pipeline, stage: etapa, title: 'Cliente novo', currency: 'BRL')

      expect(status('funil')).to eq('feito')
    end
  end

  describe 'passo 5, equipe' do
    it 'fica feito quando há mais de uma pessoa na conta' do
      user
      expect(status('equipe')).to eq('pendente')

      create(:user, account: account, role: :agent)

      expect(status('equipe')).to eq('feito')
    end

    it 'aceita ser pulado e volta a pendente quando retomado' do
      progresso.pular('equipe')
      expect(described_class.new(account: account.reload, user: user).perform.find { |p| p[:id] == 'equipe' }[:status]).to eq('pulado')

      described_class.new(account: account.reload, user: user).retomar('equipe')
      expect(described_class.new(account: account.reload, user: user).perform.find { |p| p[:id] == 'equipe' }[:status]).to eq('pendente')
    end
  end

  describe 'passo 7, campanha' do
    it 'fica feito com campanha criada' do
      expect(status('campanha')).to eq('pendente')

      create(:campaign, account: account, inbox: create(:inbox, account: account))

      expect(status('campanha')).to eq('feito')
    end
  end

  describe 'passo 8, configurações' do
    it 'fica feito com a primeira etiqueta' do
      expect(status('configuracoes')).to eq('pendente')

      create(:label, account: account)

      expect(status('configuracoes')).to eq('feito')
    end
  end

  describe 'pular' do
    it 'recusa passo que não é pulável' do
      expect { progresso.pular('chave_ia') }.to raise_error(ArgumentError, /não pode ser pulado/)
    end

    it 'recusa passo desconhecido' do
      expect { progresso.pular('inventado') }.to raise_error(ArgumentError, /desconhecido/)
    end

    it 'não esconde passo já feito: feito vence pulado' do
      progresso.pular('configuracoes')
      create(:label, account: account)

      expect(described_class.new(account: account.reload, user: user).perform.find { |p| p[:id] == 'configuracoes' }[:status]).to eq('feito')
    end
  end

  describe 'perfil do usuário' do
    it 'mostra ao agente só perfil e primeira resposta' do
      agente = create(:user, account: account, role: :agent)

      passos = described_class.new(account: account, user: agente, perfil: 'agent').perform

      expect(passos.map { |passo| passo[:id] }).to eq(%w[perfil primeira_resposta])
    end
  end
end
