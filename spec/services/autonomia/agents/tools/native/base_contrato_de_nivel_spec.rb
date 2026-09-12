require 'rails_helper'

# O NÍVEL DE CADA MÉTODO DO CONTRATO DA FERRAMENTA NATIVA (entrega 4).
#
# O contrato tem métodos de CLASSE (os textos que o job publica sem instância: `accepted_message`,
# `waiting_message`, `failure_message`, `partial_message`, `uncertain_message`) e métodos de
# INSTÂNCIA (os que precisam de conexão e parâmetros: `precheck`, `closing_deliveries`, `pedido`,
# `call`, `start`, `poll`). Definir um
# deles no nível errado não dá erro: dá uma frase que nunca sai, ou um default que ninguém chama.
#
# Foi assim que a frase de encerramento parcial da cotação — "algumas SEGURADORAS não responderam" —
# ficou dois dias sem rodar (nasceu em 08/09/2026): escrita como método de instância, enquanto o
# `AsyncRunJob` publica o fecho pela classe. O cliente lia o texto genérico do `Base` ("algumas
# consultas"). E, ao contrário, `precheck` e `closing_deliveries` tinham default de classe que
# nenhum chamador alcançava.
#
# Varre TODAS as nativas do catálogo e o CONTRATO INTEIRO — não só os seis métodos do defeito —,
# para o próximo ramo (residencial, vida…) não repetir o erro em outro método: um `async?` definido
# na instância, por exemplo, passaria despercebido e viraria ferramenta síncrona segurando o turno.
RSpec.describe Autonomia::Agents::Tools::Native::Base do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  # O que o `Registry`, o `Bound` e o job leem NA CLASSE.
  let(:textos_de_classe) do
    %i[slug tool_name description params available_for? async? openai_schema
       accepted_message waiting_message failure_message partial_message uncertain_message]
  end
  # O que o `Bound` e o job chamam NA INSTÂNCIA (`resultado_entregue?` e `resta_entregar?` são as
  # duas perguntas que o `Tools::Encerramento` faz à ferramenta antes de escolher o fecho).
  let(:trabalho_de_instancia) do
    %i[precheck closing_deliveries resultado_entregue? resta_entregar? pedido call start poll]
  end
  # Os cinco textos que saem para o cliente ou para o modelo: precisam ser frases, não só existir.
  let(:frases) { %i[accepted_message waiting_message failure_message partial_message uncertain_message] }

  Autonomia::Agents::Tools::Registry.all.each do |ferramenta|
    describe ferramenta.name do
      let(:instancia) { ferramenta.new(agent: agent, params: {}) }

      it 'define o que o catálogo, o Bound e o job leem como métodos de CLASSE, e nunca de instância' do
        textos_de_classe.each do |texto|
          expect(ferramenta).to respond_to(texto), "#{ferramenta}.#{texto} precisa existir na classe"
          expect(instancia).not_to respond_to(texto),
                                   "#{ferramenta}##{texto} de instância nunca é chamado: não vale"
        end
        frases.each { |texto| expect(ferramenta.public_send(texto)).to be_a(String) }
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

  # AS DUAS PERGUNTAS DO FECHO PARCIAL SÃO CONSERVADORAS POR PADRÃO: quem não sabe dizer se entregou
  # resultado, e se sobrou algo, não faz o fecho AFIRMAR nenhuma das duas. Um default `true` aqui
  # seria a frase inventada de volta, agora no contrato.
  it 'a ferramenta que nao redefine nao afirma que entregou resultado nem que sobrou algo' do
    crua = Class.new(described_class) do
      def self.slug = 'crua'
      def self.description = 'teste'
    end

    expect(crua.new(agent: agent, params: {}).resultado_entregue?({})).to be(false)
    expect(crua.new(agent: agent, params: {}).resta_entregar?({})).to be(false)
  end

  # O CONSTRUTOR GANHOU `run:` COM PADRÃO `nil` (entrega 8a): é o motor que passa a entregá-lo
  # quando monta a ferramenta fora do turno. Só a cotação o lê, e nenhuma nativa sobrescreve
  # `initialize` — este exemplo é o que prova a segunda metade sobre o catálogo inteiro, que é o
  # que torna a mudança inofensiva para as outras.
  it 'toda ferramenta do catalogo aceita ser montada com a linha da execucao' do
    Autonomia::Agents::Tools::Registry.all.each do |ferramenta|
      expect { ferramenta.new(agent: agent, params: {}, run: nil) }
        .not_to raise_error, "#{ferramenta} não aceita o construtor do motor"
    end
  end
end
