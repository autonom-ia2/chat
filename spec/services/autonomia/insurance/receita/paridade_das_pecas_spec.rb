require 'rails_helper'

# R21 DA RECEITA DE RAMO: AS PEÇAS DO CHAT EM PARIDADE (o lado do chat; o do adapter é `paridade-dos-ramos.test.ts`).
#
# No empresarial eu esqueci, uma de cada vez, peças que o residencial já tinha, e cada uma só apareceu num teste real.
# A lista abaixo é o que residencial e empresarial têm de fato no chat em 25/09/2026, lido no código. Todo especialista
# de `Builder::ESPECIALISTAS` fora auto tem cada peça, ou uma exceção escrita com o motivo. Auto é o ramo de partida:
# as peças nasceram dele, com outra forma.
#
# O "rótulo do item" da receita não tem peça por ramo no chat: o nome do bem é o parâmetro `item` da ferramenta, igual
# para todo ramo (`Declaracao::COMUNS`, `Faixa.descricao`, `NotaDaEquipe#cotacao_da_nota`). Por isso não está aqui.
module PecasDoChat
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  MIGRATIONS = Rails.root.join('db/migrate')
  SPECS_DO_MANUAL = Rails.root.join('spec/services/autonomia/insurance/quote_agent')

  # AS EXCEÇÕES, por ramo e peça, com o motivo. Vazia em 25/09/2026.
  EXCECOES = {}.freeze

  module_function

  def especialistas
    BUILDER::ESPECIALISTAS.reject { |dados| dados[:ramo] == 'auto' }
  end

  def pecas
    PECAS
  end

  # A migration que insere o especialista: a que declara `SLUG = '<slug>'` e escreve em `autonomia_agent_specialists`.
  def migration(slug)
    Dir[MIGRATIONS.join('*.rb').to_s].find do |caminho|
      arvore = Prism.parse_file(caminho).value
      nos(arvore).any? { |no| slug_da_migration?(no, slug) } &&
        nos(arvore).any? { |no| texto(no).include?('INSERT INTO autonomia_agent_specialists') }
    end
  end

  def slug_da_migration?(nodo, slug)
    return false unless nodo.is_a?(Prism::ConstantWriteNode) && nodo.name == :SLUG

    valor = nodo.value
    valor = valor.receiver while valor.is_a?(Prism::CallNode) && valor.name == :freeze
    valor.is_a?(Prism::StringNode) && valor.unescaped == slug
  end

  def texto(nodo)
    case nodo
    when Prism::StringNode then nodo.unescaped
    when Prism::InterpolatedStringNode then nodo.parts.select { |parte| parte.is_a?(Prism::StringNode) }.map(&:unescaped).join
    else ''
    end
  end

  # O spec do manual do ramo, se ele é o do especialista: cita o slug dele.
  def spec_do_manual(dados)
    caminho = SPECS_DO_MANUAL.join("builder_instrucao_do_especialista_#{dados[:ramo]}_spec.rb")
    return nil unless caminho.exist?

    arvore = Prism.parse_file(caminho.to_s).value
    nos(arvore).any? { |no| no.is_a?(Prism::StringNode) && no.unescaped == dados[:slug] } ? arvore : nil
  end

  # `Digest::MD5.hexdigest(...)` comparado a uma assinatura.
  def assina_md5?(arvore)
    nos(arvore).any? do |no|
      no.is_a?(Prism::CallNode) && no.name == :hexdigest && no.receiver.is_a?(Prism::ConstantPathNode) && no.receiver.name == :MD5
    end
  end

  # `PROMESSAS = { 'frase' => -> { ... }, ... }` com ao menos uma promessa.
  def promessas?(arvore)
    nos(arvore).any? do |no|
      next false unless no.is_a?(Prism::ConstantWriteNode) && no.name == :PROMESSAS

      valor = no.value
      valor = valor.receiver while valor.is_a?(Prism::CallNode) && valor.name == :freeze
      valor.is_a?(Prism::HashNode) && valor.elements.any?
    end
  end

  def nos(arvore)
    lista = []
    fila = [arvore]
    until fila.empty?
      no = fila.shift
      lista << no
      fila.concat(no.compact_child_nodes)
    end
    lista
  end

  # Peça -> como conferir. Cada conferência recebe a entrada de `ESPECIALISTAS`.
  PECAS = {
    'o resumo da entrada em EntradaDaCotacao' => lambda { |dados|
      Autonomia::Insurance::EntradaDaCotacao::CAMPOS_POR_PRODUTO.key?(dados[:ramo])
    },
    'o mock do schema do ramo' => ->(dados) { Autonomia::Insurance::Connector::Mock::SCHEMAS.key?(dados[:ramo]) },
    'a consulta grátis do ramo' => ->(dados) { BUILDER::CONSULTAS_DO_RAMO.key?(dados[:ramo]) },
    'a migration que insere o especialista nos agentes que existem' => ->(dados) { migration(dados[:slug]).present? },
    'o ensaio da migration' => lambda { |dados|
      SPECS_DO_MANUAL.join("add_#{dados[:ramo]}_specialist_to_quote_agents_spec.rb").exist?
    },
    'o manual assinado com md5' => ->(dados) { spec_do_manual(dados).then { |arvore| arvore && assina_md5?(arvore) } },
    'a tabela de promessas do manual' => ->(dados) { spec_do_manual(dados).then { |arvore| arvore && promessas?(arvore) } },
    'o fecho sem novidade' => lambda { |dados|
      Autonomia::Agents::Tools::Native::InsuranceQuote::Resultado::FECHAM_SEM_NOVIDADE.include?(dados[:ramo])
    }
  }.freeze
end

RSpec.describe 'R21: as peças do chat em paridade' do # rubocop:disable RSpec/DescribeClass
  PecasDoChat.especialistas.each do |dados|
    describe "o especialista de #{dados[:ramo]}" do
      PecasDoChat.pecas.each do |peca, confere|
        it "tem #{peca}" do
          motivo = PecasDoChat::EXCECOES.dig(dados[:ramo], peca)
          skip "exceção escrita: #{motivo}" if motivo

          expect(confere.call(dados)).to be_truthy,
                                         "#{dados[:ramo]} sem #{peca}. Residencial e empresarial têm; faça a peça, ou escreva a " \
                                         'exceção com o motivo em PecasDoChat::EXCECOES.'
        end
      end
    end
  end

  it 'toda exceção é de um ramo e de uma peça que existem' do
    ramos = PecasDoChat.especialistas.map { |dados| dados[:ramo] }

    PecasDoChat::EXCECOES.each do |ramo, pecas|
      expect(ramos).to include(ramo)
      expect(PecasDoChat.pecas.keys).to include(*pecas.keys)
      expect(pecas.values).to all(be_present)
    end
  end

  # AUTOTESTE: as conferências reconhecem a falta. Um ramo inventado não tem nenhuma das peças.
  it 'um ramo sem peça nenhuma reprova em todas' do
    inventado = { slug: 'cotacao_nautico', ramo: 'nautico', arquivo: 'especialista_nautico.md' }

    expect(PecasDoChat.pecas.values.map { |confere| confere.call(inventado) }).to all(be_falsey)
  end
end
