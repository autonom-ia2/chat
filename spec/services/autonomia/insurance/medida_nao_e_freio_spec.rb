require 'rails_helper'

# TERMO 5 DA ENTREGA 7 — NADA AQUI VIRA FREIO.
#
# A medida informa; quem decide volume é a corretora que paga. O jeito de a medida virar freio é
# banal e silencioso: alguém a chama de dentro do aceite, do `start` ou do job "só para conferir" e,
# do dia seguinte em diante, a corretora que cota mais é a que o agente para de atender. Foi assim
# que nasceu o teto de "8 por hora" removido em 10/09/2026.
#
# A guarda é por ALCANCE: a medida só pode ser NOMEADA pelas superfícies de leitura. Uma referência
# nova em qualquer outro lugar reprova aqui, e quem a escrever é obrigado a encarar a decisão em vez
# de repetir o acidente.
#
# POR AST (Prism), como a varredura de recusas: busca textual acusaria o comentário que EXPLICA a
# decisão — e uma guarda que reprova a explicação apaga o motivo junto com a regra.
RSpec.describe Autonomia::Insurance::Medida do
  # Onde a medida PODE aparecer: ela mesma, a porta da conta (a corretora vê o retorno) e a página do
  # Super Admin (a operação cobra). Nenhum arquivo de ferramenta, job ou aceite.
  let(:leitores) do
    ['app/controllers/api/v1/accounts/autonomia/insurance/measurement_controller.rb',
     'app/controllers/super_admin/insurance_measurements_controller.rb',
     'app/services/autonomia/insurance/medida.rb',
     'app/views/super_admin/insurance_measurements/show.html.erb']
  end

  let(:escritas_proibidas) do
    %w[update update! update_all create create! destroy destroy_all save save! delete_all insert]
  end

  # AS DUAS ÁRVORES: o código aberto e o overlay `enterprise/app`, que sobrescreve serviços, jobs e
  # controllers por `prepend_mod_with`. Uma varredura só de `app/**` deixaria o freio entrar pelo
  # override — o mesmo arquivo, noutra pasta.
  let(:raizes) { %w[app enterprise/app] }

  # Tudo que roda no caminho da cotação: a ferramenta, o aceite, o job, o especialista.
  let(:caminho_da_cotacao) do
    relativos(raizes.product(%w[services/autonomia/agents jobs/autonomia/agents services/autonomia/insurance])
                    .flat_map { |raiz, pasta| Dir[Rails.root.join("#{raiz}/#{pasta}/**/*.rb").to_s] })
  end

  # Onde a constante MORA. O nome simples `Medida` é a medida quando o código está, lexicalmente,
  # dentro deste módulo ou de um filho dele — é ali que `Medida.new` resolve para ela. A guarda acusa
  # pelo namespace ESCRITO em volta, inclusive na forma compacta (`class Autonomia::Insurance::X`), em
  # que o Ruby não resolveria o nome simples: dentro deste namespace, acusar a mais custa um exemplo
  # vermelho que se explica; deixar passar é o freio.
  let(:namespace_da_medida) { 'Autonomia::Insurance' }

  def relativos(caminhos)
    caminhos.map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.sort
  end

  # Sem memória: a lista é lida na hora, para ver o arquivo que um exemplo acabou de criar.
  def todos
    relativos(raizes.flat_map { |raiz| Dir[Rails.root.join("#{raiz}/**/*.{rb,erb}").to_s] })
  end

  # O nome da medida ESCRITO COMO CÓDIGO. Em `.rb`, uma constante na árvore; em `.erb`, texto (a
  # única superfície ERB desta entrega é a página do Super Admin, que é leitura declarada).
  def nomeiam_a_medida(caminhos)
    caminhos.select do |caminho|
      caminho.end_with?('.erb') ? File.read(Rails.root.join(caminho)).include?('Insurance::Medida') : constante_em?(caminho)
    end
  end

  # DUAS FORMAS DE NOMEAR, e a guarda tem de ver as duas: o caminho (`Insurance::Medida`,
  # `::Autonomia::Insurance::Medida`) em qualquer namespace, e o nome simples `Medida` quando o
  # arquivo está dentro de `Autonomia::Insurance`. Um serviço em `module Autonomia::Insurance`
  # chamando `Medida.new(...).call` passava invisível pela guarda que só olhava o caminho (rodada 6,
  # P3 do Codex) — e é o lugar mais natural para um freio nascer, ao lado da medida. Fora do
  # namespace, `Medida` é outra constante e não é acusada: guarda que grita à toa acaba desligada.
  def constante_em?(caminho)
    achou = false
    cada_no_com_namespace(VarreduraDeRecusas.arvore(caminho)) do |nodo, namespace|
      achou ||= caminho_da_medida?(nodo) || nome_simples_da_medida?(nodo, namespace)
    end
    achou
  end

  def caminho_da_medida?(nodo)
    nodo.is_a?(Prism::ConstantPathNode) && nodo.slice.end_with?('Insurance::Medida')
  end

  def nome_simples_da_medida?(nodo, namespace)
    nodo.is_a?(Prism::ConstantReadNode) && nodo.name == :Medida && dentro_do_namespace_da_medida?(namespace)
  end

  def dentro_do_namespace_da_medida?(namespace)
    namespace == namespace_da_medida || namespace.start_with?("#{namespace_da_medida}::")
  end

  # Percorre a árvore entregando cada nó e o namespace LEXICAL em que ele está — os `module`/`class`
  # que o envolvem, com o caminho escrito em cada um. É o que decide o que um nome simples significa.
  def cada_no_com_namespace(nodo, pilha = [], &)
    return if nodo.nil?

    pilha += [nodo.constant_path.slice.delete_prefix('::')] if nodo.is_a?(Prism::ModuleNode) || nodo.is_a?(Prism::ClassNode)
    yield(nodo, pilha.join('::'))
    nodo.compact_child_nodes.each { |filho| cada_no_com_namespace(filho, pilha, &) }
  end

  # Um arquivo que existe só durante o exemplo, na árvore DE VERDADE (`app/`, `enterprise/app`): a
  # prova é da guarda inteira, enumeração incluída, não de uma função com um texto na mão. O arquivo
  # e as pastas criadas para ele saem junto, aconteça o que acontecer no bloco.
  def com_arquivo_temporario(caminho, conteudo)
    completo = Rails.root.join(caminho)
    pastas_criadas = completo.dirname.ascend.take_while { |pasta| !pasta.exist? }
    FileUtils.mkdir_p(completo.dirname)
    File.write(completo, conteudo)
    yield
  ensure
    FileUtils.rm_f(completo) if completo
    Array(pastas_criadas).each { |pasta| FileUtils.rmdir(pasta) }
  end

  it 'so e nomeada pelas superficies de leitura' do
    # Act
    citam = nomeiam_a_medida(todos)

    # Assert
    expect(citam).to eq(leitores),
                     "a medida virou dependência de quem não só lê — isto é o freio entrando pela porta dos fundos:\n" \
                     "#{(citam - leitores).join("\n")}"
  end

  # O mesmo invariante dito onde ele dói: nenhum arquivo que roda durante uma cotação alcança a
  # medida. Sem isto, "quanto você já cotou este mês" acaba virando condição para cotar.
  it 'nao e alcancada de dentro do caminho da cotação' do
    citam = nomeiam_a_medida(caminho_da_cotacao) - ['app/services/autonomia/insurance/medida.rb']

    expect(citam).to be_empty, "a medida entrou no caminho da cotação:\n#{citam.join("\n")}"
  end

  # E ela não escreve: é consulta. Uma medida que gravasse estado teria como marcar quem "já usou
  # demais" — e a partir daí o freio é uma linha.
  it 'nao escreve nada' do
    escritas = []
    VarreduraDeRecusas.cada_no(VarreduraDeRecusas.arvore('app/services/autonomia/insurance/medida.rb')) do |nodo, _m|
      escritas << nodo.name.to_s if nodo.is_a?(Prism::CallNode) && escritas_proibidas.include?(nodo.name.to_s)
    end

    expect(escritas).to be_empty, "a medida passou a escrever: #{escritas.uniq.join(', ')}"
  end

  # A GUARDA PROVADA CONTRA O FREIO ESCRITO, não só contra o código que existe hoje. Cada forma de
  # nomear a medida vira um arquivo real, nas duas árvores, e a guarda tem de acusá-lo — o nome simples
  # dentro do namespace era a forma que passava invisível (rodada 6). E a forma que NÃO é a medida
  # (`Medida` de outro namespace) não pode ser acusada, senão a guarda vira ruído.
  describe 'o detector' do
    let(:formas_de_nomear) do
      {
        'o nome simples dentro de `module Autonomia::Insurance`, em app/' => [
          'app/services/autonomia/insurance/freio_de_prova.rb', <<~RUBY
            module Autonomia::Insurance
              class FreioDeProva
                def call
                  Medida.new(inicio: nil, fim: nil).por_conta
                end
              end
            end
          RUBY
        ],
        'o nome simples em modulos aninhados abaixo do namespace, em enterprise/app' => [
          'enterprise/app/services/autonomia/insurance/freios/de_prova.rb', <<~RUBY
            module Autonomia
              module Insurance
                module Freios
                  class DeProva
                    def call
                      Medida::PeriodoInvalido
                    end
                  end
                end
              end
            end
          RUBY
        ],
        'o caminho completo fora do namespace, em app/' => [
          'app/services/autonomia/agents/tools/freio_de_prova.rb', <<~RUBY
            module Autonomia::Agents::Tools
              class FreioDeProva
                def call
                  ::Autonomia::Insurance::Medida.new(inicio: nil, fim: nil, conta: nil).call
                end
              end
            end
          RUBY
        ],
        'o caminho relativo fora do namespace, em enterprise/app' => [
          'enterprise/app/jobs/autonomia/agents/freio_de_prova.rb', <<~RUBY
            class Autonomia::Agents::FreioDeProva
              def perform
                Insurance::Medida.new(inicio: nil, fim: nil, conta: nil).call
              end
            end
          RUBY
        ]
      }
    end

    it 'acusa cada forma de nomear a medida, nas duas arvores' do
      formas_de_nomear.each do |forma, (caminho, conteudo)|
        com_arquivo_temporario(caminho, conteudo) do
          expect(nomeiam_a_medida(todos) - leitores).to eq([caminho]), "a guarda não viu #{forma}"
        end
      end
    end

    it 'nao acusa Medida de outro namespace' do
      conteudo = <<~RUBY
        module Autonomia::Agents
          class FreioDeProva
            def call
              Medida.new
            end
          end
        end
      RUBY

      com_arquivo_temporario('app/services/autonomia/agents/freio_de_prova.rb', conteudo) do
        expect(nomeiam_a_medida(todos) - leitores).to be_empty
      end
    end

    # Nem as pastas que só existiram por causa dele: `enterprise/app/services/autonomia/insurance/freios`
    # não está na árvore, e um resto dela mudaria a enumeração de todo exemplo seguinte.
    it 'nao deixa o arquivo de prova nem as pastas dele para tras' do
      # Arrange — a forma cujo caminho exige pastas novas; se a árvore um dia as tiver, este exemplo
      # deixa de provar a limpeza e tem de trocar de forma.
      caminho, conteudo = formas_de_nomear['o nome simples em modulos aninhados abaixo do namespace, em enterprise/app']
      completo = Rails.root.join(caminho)
      pastas_novas = completo.dirname.ascend.take_while { |pasta| !pasta.exist? }
      expect(pastas_novas).not_to be_empty

      # Act
      com_arquivo_temporario(caminho, conteudo) { nil }

      # Assert
      expect(completo).not_to exist
      expect(pastas_novas.select(&:exist?)).to be_empty
    end
  end
end
