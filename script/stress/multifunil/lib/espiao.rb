# Instrumento só do teste: guarda o resultado de cada avaliação da IA de movimentação, que o job descarta. Sem isso,
# uma avaliação que falhou (timeout, JSON inválido) passaria em silêncio.
#   - Crm::Ai::Evaluator#perform: a avaliação de um card (Fase A e o caminho de um card da Fase B).
#   - Crm::Ai::AvaliacaoConjunta#perform: a avaliação de vários cards numa chamada (PR #1700, Fase B), quando existe.
#     Dentro dela, o Evaluator não anota de novo (a conjunta devolve o resultado de todos).
module Stress::Espiao
  CHAVE = :stress_dentro_da_conjunta
  @registro = []

  def self.anotar(card_id, resultado, origem)
    @registro << { card_id: card_id, status: resultado&.status, erro: resultado&.error,
                   sugestao: resultado&.suggestion&.id, origem: origem }
  end

  def self.ler!
    lido = @registro.dup
    @registro.clear
    lido
  end

  def self.instalar
    Crm::Ai::Evaluator.prepend(NoAvaliador)
    Crm::Ai::AvaliacaoConjunta.prepend(NaConjunta) if defined?(Crm::Ai::AvaliacaoConjunta)
  end

  module NoAvaliador
    def perform
      super.tap { |resultado| Stress::Espiao.anotar(@card.id, resultado, 'um_card') unless Thread.current[CHAVE] }
    end
  end

  module NaConjunta
    def perform
      Thread.current[CHAVE] = true
      resultados = super
      resultados.each { |card_id, resultado| Stress::Espiao.anotar(card_id, resultado, "conjunta(#{resultados.size})") }
      resultados
    ensure
      Thread.current[CHAVE] = nil
    end
  end
end
