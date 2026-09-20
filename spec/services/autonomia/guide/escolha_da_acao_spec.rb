require 'rails_helper'

RSpec.describe Autonomia::Guide::EscolhaDaAcao do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  def escolha(usuario)
    described_class.new(account: conta, user: usuario)
  end

  # O modelo fica sempre disponível e sempre devolvendo uma ação válida: assim,
  # quando o resultado é nil, foi um gate deste serviço que barrou — e não a
  # falta de credencial nem um erro engolido pelo rescue.
  def modelo_devolve(json)
    resolvedor = instance_double(Crm::Ai::CredentialResolver, resolve: 'sk-teste')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolvedor)
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create).and_return({ text: json.to_json })
  end

  describe 'quem separa pergunta de pedido' do
    # É o modelo, pela instrução — não uma lista de verbos minha. A lista já
    # deixou passar em silêncio "Configura o funil".
    it 'não propõe ação quando o modelo diz que era pergunta' do
      modelo_devolve({ acao: nil })

      expect(escolha(admin).para('Como funciona o funil no CRM?')).to be_nil
    end

    # Guarda contra a volta do filtro de vocabulário: o pedido vale escrito de
    # qualquer jeito, inclusive sem verbo de comando.
    it 'reconhece o pedido escrito de qualquer jeito' do
      modelo_devolve({ acao: 'criar_funil', nome: 'Comercial' })

      ['Configura um funil Comercial', 'Quero um funil chamado Comercial',
       'Preciso de um funil Comercial', 'Bota aí um funil Comercial'].each do |pedido|
        expect(escolha(admin).para(pedido)).not_to be_nil, "o pedido \"#{pedido}\" não foi reconhecido"
      end
    end
  end

  describe 'a permissão, que continua valendo' do
    it 'não propõe ação para agente comum' do
      modelo_devolve({ acao: 'criar_funil', nome: 'Comercial' })
      agente, = create_crm_agent(account: conta)
      expect(Crm::Ai::ResponsesClient).not_to receive(:new)

      expect(escolha(agente).para('Cria um funil chamado Comercial')).to be_nil
    end
  end

  describe 'quando o modelo responde' do
    it 'devolve a ação e os valores que a pessoa informou' do
      modelo_devolve({ acao: 'criar_funil', nome: 'Comercial', etapas: %w[Novo Fechado] })

      expect(escolha(admin).para('Cria um funil chamado Comercial')).to eq(
        { acao: 'criar_funil', dados: { nome: 'Comercial', etapas: %w[Novo Fechado] } }
      )
    end

    # A superfície é fechada: nome de ação inventado pelo modelo não vira proposta.
    it 'descarta ação que não existe no catálogo' do
      modelo_devolve({ acao: 'apagar_conta' })

      expect(escolha(admin).para('Cria um funil e apaga a conta antiga')).to be_nil
    end

    # Nome parecido em outra conta não pode alcançar nada desta.
    it 'resolve caixa e funil pelo nome, só dentro da conta' do
      create_crm_inbox(account: conta, name: 'WhatsApp', members: [admin])
      outra_conta, outro_admin = create_account_and_user
      alheio, = create_crm_pipeline(account: outra_conta, user: outro_admin, name: 'Funil de fora')
      modelo_devolve({ acao: 'ligar_caixa_ao_funil', inbox: 'WhatsApp', funil: 'Funil de fora' })

      dados = escolha(admin).para('Liga a caixa WhatsApp ao funil Funil de fora')[:dados]

      expect(dados[:inbox_id]).to eq(conta.inboxes.first.id)
      expect(dados[:pipeline_id]).to be_nil
      expect(alheio.account_id).not_to eq(conta.id)
    end
  end
end
