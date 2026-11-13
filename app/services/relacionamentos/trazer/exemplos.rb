# Os exemplos da conferência de "Trazer minha lista" (#2896): as primeiras pessoas que vão entrar, e se cada uma entra
# como cliente com o que a pessoa respondeu até agora ("sim, todas", ou os valores que ela escolheu na coluna que diz
# quem é cliente: ContactImports::Trazer::Cliente).
class Relacionamentos::Trazer::Exemplos
  def initialize(importacao)
    @importacao = importacao
  end

  def call
    pessoas = Relacionamentos::Trazer::LinhasDaPlanilha.new(@importacao).exemplos
    valores = valores_das_linhas(pessoas.pluck(:linha))
    pessoas.map { |pessoa| pessoa.except(:linha).merge(cliente: destinos.cliente?(valores.fetch(pessoa[:linha], {}))) }
  end

  private

  # { número da linha => extra_values }, numa consulta só e só quando alguma coluna diz quem é cliente.
  def valores_das_linhas(numeros)
    return {} if numeros.empty? || destinos.chaves.empty?

    @importacao.campaign_import_rows.where(row_number: numeros).pluck(:row_number, :extra_values).to_h
  end

  def destinos
    @destinos ||= ContactImports::Trazer::DestinosDaLinha.new(@importacao)
  end
end
