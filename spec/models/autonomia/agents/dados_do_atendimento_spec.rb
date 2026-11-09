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

    it 'aceita ponto, parênteses, hífen e espaço no telefone, e grava só os dígitos' do
      agent.update!(config: agent.config.merge('atendimento' => atendimento(telefone: '+55.11.94000.1234')))

      expect(agent.reload.config.dig('atendimento', 'telefone')).to eq('+5511940001234')
    end

    it 'recusa telefone inválido no atributo telefone, com a mensagem leiga, nos dois idiomas' do
      ['1140000473', '+55 11', '+', 'ligue já', '+55 11 94000#1234', '+55 11 94000-1234 ramal 2', '++5511940001234',
       '+5511'].each do |telefone|
        agent.config = agent.config.merge('atendimento' => atendimento(telefone: telefone))
        expect(agent).not_to be_valid, telefone
        expect(agent.errors.of_kind?(:telefone, :invalid)).to be(true)
        expect(agent.errors.messages_for(:telefone)).to eq([I18n.t('autonomia.agents.atendimento.telefone_invalido')])
      end

      expect(Autonomia::Agents::Agent.human_attribute_name(:telefone, locale: :pt_BR)).to eq('Telefone')
      expect(Autonomia::Agents::Agent.human_attribute_name(:endereco, locale: :pt_BR)).to eq('Endereço')
      expect(I18n.t('autonomia.agents.atendimento.telefone_invalido', locale: :pt_BR)).to include('Confira o número')
      expect(I18n.t('autonomia.agents.atendimento.telefone_invalido', locale: :en)).to include('Check the number')
    end

    it 'o telefone gravado é sempre um que serve para o cartão de contato' do
      agent.update!(config: agent.config.merge('atendimento' => atendimento))

      telefone = agent.reload.config.dig('atendimento', 'telefone')
      cartao = { 'type' => 'contact', 'name' => 'Clínica', 'phone' => telefone }
      expect(RichMessages::Types::Contact.new(cartao).error_for('')).to be_nil
    end

    it 'recusa endereço maior que o limite, no atributo endereco' do
      limite = described_class::MAX_ENDERECO
      agent.config = agent.config.merge('atendimento' => atendimento(endereco: 'a' * (limite + 1)))

      expect(agent).not_to be_valid
      expect(agent.errors.messages_for(:endereco)).to eq([I18n.t('autonomia.agents.atendimento.endereco_longo', maximo: limite)])
      agent.config = agent.config.merge('atendimento' => atendimento(endereco: 'a' * limite))
      expect(agent).to be_valid
    end

    it 'recusa atendimento que não é um par de campos em texto' do
      ['Rua das Flores', { 'endereco' => 123, 'telefone' => '' }, { 'endereco' => '', 'telefone' => ['+5511940001234'] },
       { 'endereco' => { 'rua' => 'X' }, 'telefone' => nil }].each do |valor|
        agent.config = agent.config.merge('atendimento' => valor)

        expect(agent).not_to be_valid, valor.inspect
        expect(agent.errors.messages_for(:base)).to include(I18n.t('autonomia.agents.atendimento.invalido'))
      end
    end

    it 'aceita nil nos campos (vira vazio)' do
      agent.update!(config: agent.config.merge('atendimento' => { 'endereco' => nil, 'telefone' => nil }))

      expect(agent.reload.config['atendimento']).to eq('endereco' => '', 'telefone' => '')
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
