# O andamento de uma lista que está entrando (#2896): quanto já passou e quantas pessoas são novas ou foram completadas.
# Sai das linhas da importação numa consulta só, sem depender dos contadores que o importador só grava no fim.
class Relacionamentos::Trazer::Andamento
  PASSARAM = %w[imported import_failed].freeze

  def initialize(importacao)
    @importacao = importacao
  end

  def call
    situacao = Relacionamentos::Trazer::Situacao.de(@importacao)
    total = @importacao.valid_rows
    {
      porcentagem: Relacionamentos::Trazer::Situacao.porcentagem(situacao, contagem.values.sum, total), situacao: situacao, total: total,
      novas: gravadas(ja_existia: false), completadas: gravadas(ja_existia: true)
    }
  end

  private

  # { ['imported', false] => 70, ['imported', true] => 12, ['import_failed', false] => 1 }
  def contagem
    @contagem ||= @importacao.campaign_import_rows.where(status: PASSARAM).group(:status, :was_existing_contact).count
  end

  def gravadas(ja_existia:)
    contagem.fetch(['imported', ja_existia], 0)
  end
end
