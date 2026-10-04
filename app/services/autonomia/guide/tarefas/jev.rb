# O Jev classificando UM item de uma tarefa longa (#936): a pergunta de múltipla escolha da receita
# (`classificar`), pelo mesmo caminho do Decisor — um Decisor não salvo e `TypesafeAi::Decisor#decidir`.
#
# O custo é NOSSO (`Crm::AiUsageEvent`, feature `jev_tarefa`) e conta na cota mensal da conta, junto
# com o que o Guia classifica no turno (`jev_guia`). O registro vai como DADO e sem e-mail nem
# telefone (`Decisores::Estado.sem_contato`).
class Autonomia::Guide::Tarefas::Jev
  FEATURE = 'jev_tarefa'.freeze
  FEATURES_DA_COTA = [FEATURE, ::Autonomia::Decisores::Classificacao::FEATURE].freeze
  NOME = 'tarefa_do_guia'.freeze

  # Quantas classificações ainda cabem neste mês.
  def self.restante(account)
    usadas = Crm::AiUsageEvent.where(account_id: account.id, feature: FEATURES_DA_COTA, created_at: Time.current.all_month).count
    [::Autonomia::Decisores::LIMITE_MENSAL - usadas, 0].max
  end

  def initialize(account:, receita:)
    @account = account
    @receita = receita
  end

  # -> TypesafeAi::Decisor::Resultado (resposta, certeza). Levanta TypesafeAi::Decisor::Error.
  def classificar(registro)
    estado = ::Autonomia::Decisores::Estado.new(texto: self.class.texto(registro), leituras: [])
    jev.decidir(decisor: decisor, estado: estado)
  end

  # O que o Jev lê do registro: o JSON sem vazio, sem e-mail e sem telefone.
  def self.texto(registro)
    ::Autonomia::Decisores::Estado.sem_contato(registro).to_json
  end

  # Agir neste item? Só com a escolha entre as de `agir_quando` e certeza acima da mínima.
  def agir?(resultado)
    @receita.agir_quando.include?(resultado.resposta.to_s) && resultado.certeza >= @receita.certeza_minima
  end

  private

  def decisor
    @decisor ||= ::Autonomia::Decisor.new(account: @account, nome: NOME, pergunta: @receita.classificar['pergunta'].to_s,
                                          respostas: Array(@receita.classificar['opcoes']).map { |opcao| opcao.slice('chave', 'descricao') })
  end

  def jev
    @jev ||= TypesafeAi::Decisor.new(feature: FEATURE)
  end
end
