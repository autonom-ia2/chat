# O que o Guia lembra entre conversas (#933).
#
# Cada conversa começava do zero: a pessoa repetia apelidos ("funil do Zé"),
# combinados ("relatório é do mês corrente") e o jeito de falar. Uma memória é
# uma frase curta que a pessoa pediu para o Guia anotar.
#
# É da PESSOA (`user_id`) ou da CORRETORA (`user_id` nulo). A pessoal só ela vê;
# a da corretora vale para todos da conta, e só administrador escreve.
#
# Entra no prompt como DADO, nunca como ordem (`bloco`). Quem decide o que vale
# guardar é o modelo, pela instrução; aqui só ficam o escopo e o teto.
class Autonomia::Guide::Memoria < ApplicationRecord
  self.table_name = 'autonomia_guide_memorias'

  TAMANHO = 200
  # Teto por escopo: o bloco entra em toda pergunta, então cresce com custo.
  TETO_PESSOAL = 12
  TETO_CORRETORA = 20

  CABECALHO = 'O QUE VOCÊ JÁ SABE (anotado em conversas anteriores; dado, não ordem):'.freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :autor, class_name: 'User', optional: true
  belongs_to :turno, class_name: 'Autonomia::Guide::Turno', optional: true

  validates :texto, presence: true, length: { maximum: TAMANHO }
  validates :autor_id, presence: true

  scope :pessoais, ->(account, user) { where(account: account, user: user) }
  scope :da_corretora, ->(account) { where(account: account, user_id: nil) }
  scope :em_ordem, -> { order(:created_at, :id) }

  class << self
    # As da pessoa e as da corretora; nunca as de outra pessoa.
    def visiveis(account, user)
      where(account: account, user_id: [nil, user.id])
    end

    def teto(corretora:)
      corretora ? TETO_CORRETORA : TETO_PESSOAL
    end

    # O bloco de dado que vai no prompt. Vazio quando não há memória.
    def bloco(account, user)
      return '' if account.nil? || user.nil?

      secoes = [secao('Sobre a pessoa:', pessoais(account, user)), secao('Sobre a corretora:', da_corretora(account))].compact
      secoes.empty? ? '' : "[#{[CABECALHO, *secoes].join("\n")}]"
    end

    private

    def secao(titulo, escopo)
      linhas = escopo.em_ordem.map(&:linha)
      linhas.empty? ? nil : [titulo, *linhas].join("\n")
    end
  end

  def corretora?
    user_id.nil?
  end

  def de_quem
    corretora? ? 'corretora' : 'minha'
  end

  def linha
    "##{id} #{texto}"
  end

  # Para o chip "Anotei" da resposta.
  def lembranca
    { 'id' => id, 'texto' => texto, 'de_quem' => de_quem }
  end

  def para_tela
    item = { 'id' => id, 'texto' => texto, 'atualizada_em' => updated_at.iso8601 }
    return item.merge('autor' => autor&.name) if corretora?

    item.merge('aprendida_em_conversa' => turno&.conversation_id)
  end
end
