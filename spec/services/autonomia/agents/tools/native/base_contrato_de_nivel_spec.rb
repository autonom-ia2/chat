require 'rails_helper'

# O NÍVEL DE CADA MÉTODO DO CONTRATO DA FERRAMENTA NATIVA (entrega 4).
#
# O contrato tem métodos de CLASSE (os textos que o job publica sem instância: `accepted_message`,
# `waiting_message`, `failure_message`, `partial_message`) e métodos de INSTÂNCIA (os que precisam
# de conexão e parâmetros: `precheck`, `closing_deliveries`, `call`, `start`, `poll`). Definir um
# deles no nível errado não dá erro: dá uma frase que nunca sai, ou um default que ninguém chama.
#
# Foi assim que a frase de encerramento parcial da cotação — "algumas SEGURADORAS não responderam" —
# ficou cinco dias sem rodar: escrita como método de instância, enquanto o `AsyncRunJob` publica o
# fecho pela classe. O cliente lia o texto genérico do `Base` ("algumas consultas"). E, ao contrário,
# `precheck` e `closing_deliveries` tinham default de classe que nenhum chamador alcançava.
#
# Varre TODAS as nativas do catálogo, para o próximo ramo (residencial, vida…) não repetir o erro.
RSpec.describe Autonomia::Agents::Tools::Native::Base do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:textos_de_classe) { %i[accepted_message waiting_message failure_message partial_message] }
  let(:trabalho_de_instancia) { %i[precheck closing_deliveries] }

  Autonomia::Agents::Tools::Registry.all.each do |ferramenta|
    describe ferramenta.name do
      let(:instancia) { ferramenta.new(agent: agent, params: {}) }

      it 'define os textos que o job publica como métodos de CLASSE, e nunca de instância' do
        textos_de_classe.each do |texto|
          expect(ferramenta).to respond_to(texto), "#{ferramenta}.#{texto} precisa existir na classe"
          expect(ferramenta.public_send(texto)).to be_a(String)
          expect(instancia).not_to respond_to(texto),
                                   "#{ferramenta}##{texto} de instância nunca é chamado: a frase não sai"
        end
      end

      it 'define a conferência e as entregas de fechamento como métodos de INSTÂNCIA, e nunca de classe' do
        trabalho_de_instancia.each do |metodo|
          expect(instancia).to respond_to(metodo), "#{ferramenta}##{metodo} precisa existir na instância"
          expect(ferramenta).not_to respond_to(metodo),
                                    "#{ferramenta}.#{metodo} de classe nunca é chamado: o default não vale"
        end
      end
    end
  end

  # O default do `Base` vale para a ferramenta que não conhece conferência nem fechamento.
  it 'a ferramenta que nao redefine herda conferencia nula e fechamento vazio na instancia' do
    crua = Class.new(described_class) do
      def self.slug = 'crua'
      def self.description = 'teste'
    end

    expect(crua.new(agent: agent, params: {}).precheck).to be_nil
    expect(crua.new(agent: agent, params: {}).closing_deliveries({})).to eq([])
  end
end
