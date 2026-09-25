# Assinatura combinada com a frente A do #680 (empresa e contato). A implementação mora na branch
# feat/680-a-empresa-contato; este arquivo só existe para a frente B chamar a mesma interface e some no merge.
class Autonomia::Prospecting::CompanyUpserter
  Result = Struct.new(:company, :created, keyword_init: true)

  def initialize(lead:)
    @lead = lead
  end

  def perform
    raise NotImplementedError, 'Autonomia::Prospecting::CompanyUpserter vem da frente A do #680'
  end
end
