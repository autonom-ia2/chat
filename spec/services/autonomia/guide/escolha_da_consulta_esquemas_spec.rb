require 'rails_helper'

# Em 20/09/2026 o Guia subiu para produção com os dois schemas no formato errado.
# A OpenAI recusou com 400 em toda pergunta, o `rescue` engoliu, e o usuário viu
# "Houve um erro ao gerar a resposta" — leitura e ação mortas, sem nada vermelho
# no log da aplicação.
#
# Os testes não pegaram porque todos dublavam o ResponsesClient: eu verifiquei o
# que eu mesmo tinha inventado, nunca o contrato real. Este arquivo testa o
# contrato: o formato que `Crm::Ai::ResponsesClient` monta e as regras do modo
# estrito da OpenAI, que é como o cliente sempre chama.
RSpec.describe Autonomia::Guide::EscolhaDaConsulta do
  # Toda propriedade em `required`, todo objeto com `additionalProperties: false`,
  # e nenhum objeto de chave livre — as três coisas que o modo estrito exige.
  def verificar_estrito!(node, caminho = 'raiz')
    return unless node.is_a?(Hash)

    if Array(node[:type]).include?('object')
      expect(node[:properties]).to be_present, "#{caminho}: objeto sem properties"
      expect(node[:additionalProperties]).to be(false), "#{caminho}: falta additionalProperties: false"
      expect(node[:required]).to match_array(node[:properties].keys.map(&:to_s)),
                                 "#{caminho}: required tem que listar TODA propriedade"
    end

    node[:properties]&.each { |nome, filho| verificar_estrito!(filho, "#{caminho}.#{nome}") }
    verificar_estrito!(node[:items], "#{caminho}[]")
  end

  [described_class, Autonomia::Guide::EscolhaDaAcao].each do |servico|
    describe servico.name do
      let(:esquema) { servico::ESQUEMA }

      # Era exatamente isto que faltava: o cliente lê `schema[:schema]`, e eu
      # passei o JSON Schema cru, então ele mandava `schema: null`.
      it 'vem no formato que o ResponsesClient monta', :aggregate_failures do
        expect(esquema[:name]).to be_present
        expect(esquema[:schema]).to be_a(Hash)
        expect(esquema[:schema][:type]).to eq('object')
      end

      it 'obedece o modo estrito em todos os níveis' do
        expect { verificar_estrito!(esquema[:schema]) }.not_to raise_error
      end

      # O corpo do pedido que sai daqui é o que a OpenAI valida. Se `schema` for
      # nil, a chamada volta 400 e o Guia emudece.
      it 'produz um corpo de requisição com o schema preenchido' do
        cliente = Crm::Ai::ResponsesClient.new(credential: { api_key: 'sk-teste' }, feature: 'teste')
        corpo = cliente.send(:base_body, 'gpt-4.1-mini', 'instrução', 'entrada', esquema, 'low')

        expect(corpo.dig(:text, :format, :schema)).to eq(esquema[:schema])
      end
    end
  end
end
