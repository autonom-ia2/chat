require 'rails_helper'

# #1479 / #2723 — "Endereço e telefone" do agente: `config['atendimento'] = { 'endereco', 'telefone' }`. A regra mora no
# model, então vale para todo caminho que grava com validação (a API, o Construtor, a volta de versão, `update!`).
# Os caminhos que gravam sem validação (`update_columns`, `jsonb_set`) só tocam outras chaves e preservam esta.
RSpec.describe Autonomia::Agents::DadosDoAtendimento do
  let(:account) { conta_da_fase2 }
  let(:user) { create(:user, account: account) }
  let(:agent) { criar_principal(account, config: { 'with_knowledge' => false, 'handoff_strategy' => 'none' }) }

  def atendimento(endereco: 'Rua das Flores, 120, Centro', telefone: '+5511940001234')
    { 'endereco' => endereco, 'telefone' => telefone }
  end

  describe 'gravar pelo update!' do
    it 'grava o endereço sem espaços sobrando e o telefone em E.164' do
      agent.update!(config: agent.config.merge('atendimento' => atendimento(endereco: '  Rua das Flores,   120  ',
                                                                            telefone: '+55 (11) 94000-1234')))

      expect(agent.reload.config['atendimento']).to eq('endereco' => 'Rua das Flores, 120', 'telefone' => '+5511940001234')
      expect(agent.config['handoff_strategy']).to eq('none')
    end

    it 'aceita os dois vazios e ignora chave estranha' do
      agent.update!(config: agent.config.merge('atendimento' => { 'endereco' => '', 'telefone' => '', 'mapa' => 'x' }))

      expect(agent.reload.config['atendimento']).to eq('endereco' => '', 'telefone' => '')
    end

    it 'recusa telefone inválido com a mensagem leiga, nos dois idiomas' do
      ['1140000473', '+55 11', '+', 'ligue já'].each do |telefone|
        agent.config = agent.config.merge('atendimento' => atendimento(telefone: telefone))
        expect(agent).not_to be_valid
        expect(agent.errors.full_messages).to include(I18n.t('autonomia.agents.atendimento.telefone_invalido'))
      end

      expect(I18n.t('autonomia.agents.atendimento.telefone_invalido', locale: :pt_BR)).to include('telefone')
      expect(I18n.t('autonomia.agents.atendimento.telefone_invalido', locale: :en)).to include('phone')
    end

    it 'recusa endereço maior que o limite' do
      limite = described_class::MAX_ENDERECO
      agent.config = agent.config.merge('atendimento' => atendimento(endereco: 'a' * (limite + 1)))

      expect(agent).not_to be_valid
      expect(agent.errors.full_messages).to include(I18n.t('autonomia.agents.atendimento.endereco_longo', maximo: limite))
      agent.config = agent.config.merge('atendimento' => atendimento(endereco: 'a' * limite))
      expect(agent).to be_valid
    end

    it 'recusa atendimento que não é um par de campos' do
      agent.config = agent.config.merge('atendimento' => 'Rua das Flores')

      expect(agent).not_to be_valid
      expect(agent.errors.full_messages).to include(I18n.t('autonomia.agents.atendimento.invalido'))
    end

    it 'salvar outra coisa não apaga nem revalida o atendimento' do
      agent.update!(config: agent.config.merge('atendimento' => atendimento))

      agent.update!(config: agent.reload.config.merge('response_window' => 'always'), tone: 'cordial')

      expect(agent.reload.config['atendimento']).to eq(atendimento)
    end
  end

  describe 'gravar pelo Construtor (apply_builder_config!)' do
    def aplicar(config)
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: user, status: :processing,
                                                      build_token: SecureRandom.hex(4))
      agent.apply_builder_config!(thread.build_token, { tone: 'cordial', config: config })
    end

    it 'o ajuste não apaga o atendimento gravado' do
      agent.update!(config: agent.config.merge('atendimento' => atendimento))

      expect(aplicar('guardrails' => ['Não fale de preço'])).to be(true)

      expect(agent.reload.config['atendimento']).to eq(atendimento)
      expect(agent.config['guardrails']).to eq(['Não fale de preço'])
    end

    it 'a mesma validação: telefone inválido não grava' do
      expect { aplicar('atendimento' => atendimento(telefone: '12345')) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(agent.reload.config).not_to have_key('atendimento')
    end
  end

  describe 'voltar a uma versão (restore_instruction!)' do
    it 'não apaga o atendimento gravado depois da versão' do
      agent.record_instruction_version!(reason: 'manual_edit', created_by: user)
      versao = agent.instruction_versions.last
      agent.update!(instruction: 'Outra instrução', config: agent.config.merge('atendimento' => atendimento))

      agent.restore_instruction!(versao, created_by: user)

      expect(agent.reload.config['atendimento']).to eq(atendimento)
    end
  end
end
