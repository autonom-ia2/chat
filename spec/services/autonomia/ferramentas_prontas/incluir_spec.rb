require 'rails_helper'

# #2858 (F0): o "Incluir" (o serviço que a tela da F2 chama), a ferramenta pronta no modelo e o uso por conta.
RSpec.describe Autonomia::FerramentasProntas::Incluir do
  let(:account) { create(:account) }
  let(:outra_conta) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { criar_agente(account) }

  def criar_agente(conta, tipo: 'custom')
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bot', agent_type: tipo, status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def incluir(fonte = 'cep', conta: account, agente: agent, usar_quando: 'o cliente informar o CEP')
    described_class.new(account: conta, agent: agente, fonte: fonte, usar_quando: usar_quando, user: user).call
  end

  def recusa
    yield
    nil
  rescue described_class::Recusado => e
    e.motivo
  end

  before { ligar_prontas(account) }

  it 'cria a chave interna da conta na fonte e a ferramenta pronta no agente, sem link digitado' do
    resultado = incluir

    expect(resultado.acesso).to have_attributes(account_id: account.id, fonte: 'cep', incluida_por_id: user.id, cortada_em: nil)
    expect(resultado.acesso.chave).to start_with('fp_')
    expect(resultado.ferramenta).to have_attributes(
      fonte_pronta: 'cep', slug: 'pronta_cep', name: 'Endereço pelo CEP', enabled: true, endpoint_url: '',
      description: 'o cliente informar o CEP', headers_config: [], param_schema: [],
      timeout_seconds: Autonomia::FerramentasProntas::Fontes::Cep::FONTE.prazo_maximo + 1
    )
  end

  it 'incluir de novo nao duplica: atualiza a frase e religa' do
    primeira = incluir
    primeira.ferramenta.update!(enabled: false)

    segunda = incluir(usar_quando: 'o cliente mandar o CEP da casa')

    expect(segunda.acesso.id).to eq(primeira.acesso.id)
    expect(segunda.ferramenta.reload).to have_attributes(id: primeira.ferramenta.id, enabled: true, description: 'o cliente mandar o CEP da casa')
    expect(Autonomia::FerramentasProntas::Acesso.count).to eq(1)
  end

  it 'a mesma chave serve a dois agentes da conta, e cada conta tem a sua' do
    ligar_prontas(outra_conta)
    a = incluir
    b = incluir(agente: criar_agente(account))
    c = described_class.new(account: outra_conta, agent: criar_agente(outra_conta), fonte: 'cep').call

    expect(b.acesso.id).to eq(a.acesso.id)
    expect(c.acesso.id).not_to eq(a.acesso.id)
    expect(c.acesso.chave).not_to eq(a.acesso.chave)
  end

  it 'recusa com a flag desligada, para a Lia, agente de outra conta e fonte fora do catalogo' do
    expect(recusa { incluir(conta: outra_conta, agente: criar_agente(outra_conta)) }).to eq('desligada')
    expect(recusa { incluir(agente: criar_agente(account, tipo: 'insurance_quote')) }).to eq('agente_de_cotacao')
    expect(recusa { incluir(agente: criar_agente(outra_conta)) }).to eq('agente_de_outra_conta')
    expect(recusa { incluir('placa') }).to eq('fonte_desconhecida')
    expect(recusa { described_class.new(account: account, agent: agent, fonte: 'cep', user: create(:user)).call }).to eq('pessoa_de_outra_conta')
    expect(Autonomia::Agents::Tool.count).to eq(0)
    expect(Autonomia::FerramentasProntas::Acesso.count).to eq(0)
  end

  it 'recusa quando uma ferramenta manual do agente ja usa o nome da funcao' do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Minha', slug: 'pronta_cep',
                                    endpoint_url: 'https://api.exemplo.test/cep', http_method: 'GET')

    expect(recusa { incluir }).to eq('nome_em_uso')
  end

  describe 'a ferramenta pronta no modelo' do
    it 'nao aceita link, cabecalho, corpo, recorte nem parametros digitados' do
      tool = incluir.ferramenta
      tool.assign_attributes(endpoint_url: 'https://fora.exemplo.test/x', headers_config: [{ key: 'x-a', value: 'b' }],
                             request_body_template: '{}', response_mapping: { 'template' => '{{r}}' },
                             param_schema: [{ name: 'q', type: 'string' }])

      expect(tool).not_to be_valid
      expect(tool.errors.attribute_names).to include(:endpoint_url, :headers_config, :request_body_template, :response_mapping, :param_schema)
    end

    it 'nao aceita fonte fora do catalogo' do
      tool = incluir.ferramenta
      tool.fonte_pronta = 'placa'

      expect(tool).not_to be_valid
    end

    it 'o schema vem do catalogo, com a frase da conta e strict' do
      schema = incluir.ferramenta.openai_schema

      expect(schema).to include(name: 'pronta_cep', strict: true)
      expect(schema[:description]).to end_with('Use quando: o cliente informar o CEP')
      expect(schema[:parameters]).to match(type: 'object', properties: { 'cep' => { 'type' => 'string', 'description' => a_kind_of(String) } },
                                           required: ['cep'], additionalProperties: false)
    end

    it 'a fonte com varias consultas e uma ferramenta so, e o modelo escolhe a consulta' do
      schema = incluir('fipe').ferramenta.openai_schema

      expect(schema[:parameters][:properties]['consulta']).to include('enum' => %w[marcas modelos preco])
      expect(schema[:parameters][:required]).to match_array(schema[:parameters][:properties].keys)
      expect(schema[:parameters][:properties]['ano']['type']).to eq(%w[integer null])
    end
  end

  describe 'uso por conta' do
    it 'a conta A nunca ve o uso da conta B' do
      ligar_prontas(outra_conta)
      incluir
      described_class.new(account: outra_conta, agent: criar_agente(outra_conta), fonte: 'cnpj').call
      Autonomia::FerramentasProntas::Uso.reservar!(account_id: account.id, fonte: 'cep', limite: 10)
      Autonomia::FerramentasProntas::Uso.reservar!(account_id: outra_conta.id, fonte: 'cnpj', limite: 10)
      Autonomia::FerramentasProntas::Uso.anotar!(account_id: outra_conta.id, fonte: 'cnpj', desfecho: 'sem_resposta',
                                                 motivos: ['brasilapi.erro_da_fonte'])

      da_a = Autonomia::FerramentasProntas::RelatorioDeUso.da_conta(account)
      da_b = Autonomia::FerramentasProntas::RelatorioDeUso.da_conta(outra_conta)

      expect(da_a.map { |linha| linha['fonte'] }).to eq(['cep'])
      expect(da_a.sole).to include('consultas' => 1, 'sem_resposta' => 0, 'motivos' => {}, 'limite_do_dia' => 300, 'cortada' => false)
      expect(da_b.sole).to include('fonte' => 'cnpj', 'sem_resposta' => 1, 'motivos' => { 'brasilapi.erro_da_fonte' => 1 })
    end
  end
end
