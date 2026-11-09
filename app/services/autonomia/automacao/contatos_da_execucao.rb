# G58 (#2779, exemplo 9, passo 4): os contatos que os passos anteriores desta execução criaram, para o passo campanha com
# `publico: desta_execucao`. É o "monta a campanha e manda" logo depois do "cria um card para cada empresa": vai só para
# as empresas desta vez, não para todo contato com a etiqueta do mês.
#
# - Lê os registros `ok` desta execução dos passos que criam card ou contato (TIPOS_QUE_CRIAM, achados na receita da
#   versão em que a execução entrou), no mesmo padrão do EnviosDaExecucao. O card pulado com `card_ja_existe` não entra:
#   a empresa não foi criada nesta vez.
# - Contrato com a G21 (#2706) e o G4: os dados do registro trazem `card_id`/`card_ids` e `contato_id`/`contato_ids`. O
#   card vira o contato dele (Crm::Card#contact_id), na conta.
# - Fica `fora` quem ligou a automação não alcança (Acesso#alcanca?, a mesma pergunta dos outros passos) e quem não
#   pode receber (ConversationAudience::Reach: pediu para não receber, ou sem telefone e sem e-mail).
class Autonomia::Automacao::ContatosDaExecucao
  # `prospeccao` chega com a G21; até lá o esquema não tem esse passo, e a lista só casa com `card`.
  TIPOS_QUE_CRIAM = %w[card prospeccao].freeze
  CHAVES_DE_CONTATO = %w[contato_id contato_ids].freeze
  CHAVES_DE_CARD = %w[card_id card_ids].freeze

  def initialize(execucao:)
    @execucao = execucao
    @conta = execucao.account
  end

  # Os contatos que entram no Público, em ordem de id.
  def dentro = separados.first

  # Quantos ficaram de fora (sem alcance de quem ligou ou sem poder receber).
  def fora = separados.last.size

  private

  def separados
    @separados ||= todos.partition { |contato| acesso.alcanca?(contato) && ::ConversationAudience::Reach.reason_for(contato).nil? }
  end

  def todos
    dados = registros
    ids = ids_em(dados, CHAVES_DE_CONTATO) + @conta.crm_cards.where(id: ids_em(dados, CHAVES_DE_CARD)).pluck(:contact_id)
    @conta.contacts.where(id: ids.compact.uniq).order(:id).to_a
  end

  def registros
    passos = ::Autonomia::Automacao::Receita.new(@execucao.versao.receita, conta: @conta, account_user: nil).passos
    ids = passos.select { |passo| TIPOS_QUE_CRIAM.include?(passo['tipo']) }.pluck('id')
    ids.empty? ? [] : @execucao.registros.where(resultado: 'ok', passo: ids).pluck(:dados)
  end

  def ids_em(dados, chaves)
    dados.flat_map { |item| item.to_h.values_at(*chaves).flat_map { |valor| Array(valor) } }.grep(Integer)
  end

  def acesso = (@acesso ||= ::Autonomia::Automacao::Acesso.new(@execucao.automacao))
end
