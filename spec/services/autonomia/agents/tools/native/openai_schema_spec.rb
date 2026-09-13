require 'rails_helper'

# O SCHEMA QUE A OPENAI ACEITA — e o defeito que deixou um agente mudo em produção.
#
# Em 08/09/2026, a Lia foi ligada a uma caixa de WhatsApp real e não respondeu nada. O log do worker
# mostrou por quê: `Invalid schema for function 'consultar_condicoes_gerais': 'required' is required
# to be supplied and to be an array including every key in properties. Missing 'ramo'`.
#
# Em `strict: true` não existe campo fora de `required`. Uma ferramenta com UM parâmetro opcional
# derrubava a chamada INTEIRA — não a ferramenta, o turno todo —, e o agente ficava em silêncio.
RSpec.describe Autonomia::Agents::Tools::Native::Base do
  # O loop abaixo roda na CARGA do arquivo. Se o Registry ficasse vazio, o arquivo passaria verde
  # sem exercitar ferramenta nenhuma — e o defeito que ele existe para pegar voltaria em silêncio.
  it 'tem ferramentas para exercitar' do
    expect(Autonomia::Agents::Tools::Registry.all).not_to be_empty
  end

  # Toda ferramenta nativa passa por aqui. Uma nova com parâmetro opcional falha neste exemplo antes
  # de chegar a uma conversa de verdade.
  Autonomia::Agents::Tools::Registry.all.each do |tool|
    describe tool.slug do
      let(:schema) { tool.openai_schema }
      let(:props) { schema[:parameters][:properties] }

      it 'lista TODA chave de properties em required' do
        expect(schema[:parameters][:required]).to match_array(props.keys)
      end

      it 'diz que e opcional pelo tipo, e nao pela ausencia em required' do
        opcionais = tool.params.select { |p| p['required'] == false }.pluck('name')

        opcionais.each do |nome|
          expect(props[nome]['type']).to include('null'),
                                         "#{tool.slug}.#{nome} é opcional mas o tipo não aceita null"
        end
      end

      # `String` e não Array: é assim que se diz "obrigatório" em strict. O parâmetro `object` sai da
      # recursão com chaves de SÍMBOLO (`objeto` as monta assim), e o de tipo simples com chaves de
      # texto — o que importa nos dois é o tipo não aceitar `null`.
      it 'mantem obrigatorio como tipo simples' do
        obrigatorios = tool.params.reject { |p| p['required'] == false }.pluck('name')

        obrigatorios.each do |nome|
          expect(props[nome]['type'] || props[nome][:type]).to be_a(String)
        end
      end

      # A CHAVE REPETIDA É HTTP 400 NA CHAMADA INTEIRA, e o agente fica mudo (`has non-unique
      # elements`, medido em 12/09/2026). `match_array` acima não pega: ele compara os dois lados,
      # e os dois carregam a duplicata.
      it 'nao repete chave em required' do
        expect(schema[:parameters][:required].uniq.size).to eq(props.keys.size)
      end
    end
  end

  # A ferramenta que quebrou em produção, nomeada.
  describe 'consultar_condicoes_gerais' do
    it 'declara ramo como opcional sem tirá-lo de required' do
      schema = Autonomia::Agents::Tools::Native::InsuranceGeneralConditions.openai_schema

      expect(schema[:parameters][:required]).to include('ramo')
      # A ordem dentro do array não importa para a OpenAI; o que importa é `null` estar lá.
      expect(schema[:parameters][:properties]['ramo']['type']).to match_array(%w[string null])
    end
  end

  # A de cotação tem NOVE opcionais — quebraria pelo mesmo motivo. Ela é reservada pelo especialista,
  # que só roda quando o principal o chama; o log de 08/09 mostra a chamada do principal falhando
  # antes disso, então esta ferramenta nunca chegou a ser exercitada em produção.
  describe 'cotar_seguro' do
    it 'declara os opcionais comuns aceitando null' do
      schema = Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema
      opcionais = schema[:parameters][:properties].select { |_, v| v['type'].is_a?(Array) }

      expect(opcionais.keys).to match_array(%w[cpf nome cep numero dados])
      expect(schema[:parameters][:required]).to include(*opcionais.keys)
    end

    # ENTREGA 2: os campos de auto vêm do schema do adapter guardado na conexão da conta, ANINHADOS
    # por grupo — e em strict mode cada grupo é um objeto anulável com todas as folhas em
    # `required`, cada folha anulável. Um grupo ou uma folha fora de `required` derrubaria a
    # chamada inteira, como em 08/09.
    it 'com a conta conectada, declara os grupos de auto aninhados, todos anulaveis e em required' do
      account = create(:account)
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                               status: :active, enabled: true, instruction: 'Atenda.')
      enable_test_encryption!
      record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })

      schema = with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') do
        Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema(agent)
      end
      props = schema[:parameters][:properties]

      expect(props.keys).to include('produto', 'cpf', 'vehicle', 'quotation', 'coverage')
      expect(schema[:parameters][:required]).to match_array(props.keys)
      veiculo = props['vehicle']
      expect(veiculo[:type]).to match_array(%w[object null])
      expect(veiculo[:additionalProperties]).to be(false)
      expect(veiculo[:required]).to match_array(veiculo[:properties].keys)
    end

    it 'com a conta conectada, cada folha e anulavel e leva a descricao do adapter com os valores' do
      account = create(:account)
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                               status: :active, enabled: true, instruction: 'Atenda.')
      enable_test_encryption!
      record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })

      schema = with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') do
        Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema(agent)
      end
      veiculo = schema[:parameters][:properties]['vehicle']

      expect(veiculo[:properties]['plate']['type']).to match_array(%w[string null])
      expect(veiculo[:properties]['youngDriver']['type']).to match_array(%w[boolean null])
      expect(veiculo[:properties]['trackerCode']['description']).to include('Valores:')
      expect(schema[:parameters][:properties]['quotation'][:properties]['previousInsurerCode']['description']).to include('657=')
    end

    it 'mantem produto obrigatorio' do
      schema = Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema

      expect(schema[:parameters][:properties]['produto']['type']).to eq('string')
    end
  end
end
