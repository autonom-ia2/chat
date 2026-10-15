require 'rails_helper'

# Tema 14 (#1434): o Specialist que aponta para OUTRO agente da conta (`delegate_agent_id`). A instrução, a base e as
# ferramentas vêm do agente apontado. O ajudante é um agente interno, marcado como ajudante pelo vínculo; profundidade 1.
RSpec.describe Autonomia::Agents::Specialist do
  let(:conta) { conta_da_fase2 }
  let(:principal) { criar_principal(conta) }
  let(:ajudante) { criar_ajudante(conta) }

  describe 'o vínculo' do
    it 'nasce sem instrução própria: quem manda é o agente apontado' do
      vinculo = vincular(principal, ajudante)

      expect(vinculo).to be_delegado
      expect(vinculo.instruction).to eq('')
      expect(vinculo.account_id).to eq(conta.id)
    end

    it 'exige o "quando chamar"' do
      vinculo = described_class.new(agent: principal, delegate: ajudante, name: ajudante.name, description: '')

      expect(vinculo).not_to be_valid
      expect(vinculo.errors[:description]).to be_present
    end

    it 'um principal tem no máximo um vínculo com o mesmo ajudante' do
      vincular(principal, ajudante)
      repetido = described_class.new(agent: principal, delegate: ajudante, name: 'Outro nome', description: 'x')

      expect(repetido).not_to be_valid
    end

    it 'o especialista sem delegate continua exigindo instrução' do
      sem = described_class.new(agent: principal, name: 'Auto', description: 'cotar', instruction: '')

      expect(sem).not_to be_valid
      expect(sem.errors[:instruction]).to be_present
    end
  end

  describe 'quem pode ser principal e quem pode ser ajudante' do
    def recusa(principal_do_vinculo, ajudante_do_vinculo)
      vinculo = described_class.new(agent: principal_do_vinculo, delegate: ajudante_do_vinculo, name: 'X',
                                    description: 'quando precisar')
      expect(vinculo).not_to be_valid
      vinculo.errors.full_messages
    end

    it 'recusa ajudante de outra conta (isolamento)' do
      de_fora = criar_ajudante(conta_da_fase2)

      expect(recusa(principal, de_fora)).to be_present
    end

    it 'recusa um Copiloto da equipe já existente como ajudante (decisão c): só quem nasceu ajudante' do
      mensagens = recusa(principal, criar_copiloto(conta))

      expect(mensagens.join).to include(I18n.t('autonomia.agents.ajudante.sem_marca'))
    end

    it 'aceita o agente criado com a marca de origem' do
      expect(vincular(principal, ajudante)).to be_persisted
    end

    it 'recusa o agente que fala com cliente como ajudante: o ajudante é interno' do
      expect(recusa(principal, criar_principal(conta, nome: 'Maria'))).to be_present
    end

    it 'recusa o agente interno como principal: ajudante não chama ajudante (profundidade 1)' do
      outro_ajudante = criar_ajudante(conta, nome: 'Regras do Residencial')

      expect(recusa(ajudante, outro_ajudante)).to be_present
    end

    it 'recusa o ajudante que já tem ajudante (profundidade 1, mesmo com dado forjado)' do
      neto = criar_ajudante(conta, nome: 'Neto')
      described_class.new(agent: ajudante, account: conta, delegate: neto, name: 'Neto', slug: 'neto', description: 'x',
                          instruction: '').save!(validate: false)

      expect(recusa(principal, ajudante)).to be_present
    end

    it 'recusa a Lia nos dois lados: ela não muda' do
      lia = criar_principal(conta, nome: 'Lia')
      lia.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations -- só o tipo importa
      lia_interna = criar_ajudante(conta, nome: 'Lia interna')
      lia_interna.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

      expect(recusa(lia, ajudante)).to be_present
      expect(recusa(principal, lia_interna)).to be_present
    end

    it 'recusa o agente de sistema (o Guia) nos dois lados' do
      guia = criar_ajudante(conta, nome: 'Guia', config: { 'system_key' => 'guia', 'with_knowledge' => false, 'papel' => 'ajudante' })

      expect(recusa(principal, guia)).to be_present
    end

    it 'recusa como principal um agente em rascunho (revisão do PR2)' do
      rascunho = criar_principal(conta, nome: 'Rascunho', status: :draft, enabled: false)

      expect(recusa(rascunho, ajudante)).to include(a_string_including(I18n.t('autonomia.agents.ajudante.principal_rascunho')))
    end

    it 'recusa como principal um agente com a marca de ajudante, mesmo que fale com cliente (dado forjado)' do
      marcado = criar_principal(conta, nome: 'Marcado', config: { 'with_knowledge' => false, 'papel' => 'ajudante' })

      expect(recusa(marcado, ajudante)).to include(a_string_including(I18n.t('autonomia.agents.ajudante.principal_ajudante')))
    end

    it 'recusa o agente apontando para si mesmo' do
      expect(recusa(principal, principal)).to be_present
    end
  end

  describe 'o que o vínculo empresta do agente apontado' do
    it 'a instrução é a do ajudante, com o aviso de que ele responde a outro agente e nunca ao cliente' do
      vinculo = vincular(principal, ajudante)

      instrucao = vinculo.effective_instruction

      expect(instrucao).to include('Você conhece as regras do produto Auto.')
      expect(instrucao).to include('Joana', 'nunca fala com o cliente')
    end

    it 'a descrição da função carrega o "quando chamar"' do
      vinculo = vincular(principal, ajudante, quando: 'Quando a dúvida for sobre franquia do Auto')

      expect(vinculo.openai_schema[:description]).to include('Quando a dúvida for sobre franquia do Auto')
    end

    it 'as ferramentas são as do ajudante e não reservam nada do principal' do
      Autonomia::Agents::Tool.create!(account: conta, agent: ajudante, name: 'Tabela', slug: 'tabela_auto',
                                      endpoint_url: 'https://adapters.example.com/tabela', param_schema: [])
      Autonomia::Agents::Tool.create!(account: conta, agent: principal, name: 'Agenda', slug: 'agenda_da_joana',
                                      endpoint_url: 'https://adapters.example.com/agenda', param_schema: [])
      vinculo = vincular(principal, ajudante)

      expect(vinculo.tools.map(&:slug)).to eq(['tabela_auto'])
      expect(vinculo.ferramentas_do_sistema).to eq([])
    end
  end

  describe 'onde o ajudante trabalha' do
    it 'o ajudante vinculado tem onde trabalhar e não fala com cliente' do
      vincular(principal, ajudante)

      expect(ajudante.reload.tem_onde_trabalhar?).to be(true)
      expect(ajudante.atende_cliente?).to be(false)
    end

    it 'o ajudante não aceita caixa' do
      inbox = create(:inbox, account: conta)
      vincular(principal, ajudante)

      result = Autonomia::Agents::Operate::InboxConnector.new(agent: ajudante, inbox: inbox).perform(connect: true)

      expect(result.success?).to be(false)
    end
  end
end
