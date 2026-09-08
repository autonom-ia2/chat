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

      it 'mantem obrigatorio como tipo simples' do
        obrigatorios = tool.params.reject { |p| p['required'] == false }.pluck('name')

        obrigatorios.each do |nome|
          expect(props[nome]['type']).to be_a(String)
        end
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
    it 'declara os nove opcionais aceitando null' do
      schema = Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema
      opcionais = schema[:parameters][:properties].select { |_, v| v['type'].is_a?(Array) }

      expect(opcionais.keys).to match_array(%w[cpf nome cep numero dados placa renovacao bonus sinistros])
      expect(schema[:parameters][:required]).to include(*opcionais.keys)
    end

    it 'mantem produto obrigatorio' do
      schema = Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema

      expect(schema[:parameters][:properties]['produto']['type']).to eq('string')
    end
  end
end
