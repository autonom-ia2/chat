# G58 (#2779, exemplo 9, passo 4): os contatos que os passos anteriores desta execução criaram, para o passo campanha com
# `publico: desta_execucao`. É o "monta a campanha e manda" logo depois do "cria um card para cada empresa": vai só para
# as empresas desta vez, não para todo contato com a etiqueta do mês.
#
# - Lê os registros `ok` desta execução dos passos que criam card ou contato (TIPOS_QUE_CRIAM, achados na receita da
#   versão em que a execução entrou), no mesmo padrão do EnviosDaExecucao. O card pulado com `card_ja_existe` não entra:
#   a empresa não foi criada nesta vez. A lista é a única: o salvar (PassoDeCampanha) e o editor (o catálogo marca o
#   passo com `cria_contatos`) leem daqui.
# - Contrato com a G21 (#2706) e o G4: os dados do registro trazem `card_id`/`card_ids` e `contato_id`/`contato_ids`. O
#   card vira o contato dele (Crm::Card#contact_id), na conta.
# - Quem ligou a automação precisa alcançar cada contato (Acesso#alcanca?, a mesma pergunta dos outros passos). Quem
#   não alcança vai para `sem_alcance`, e o passo pausa a automação (`sem_acesso`) em vez de mandar a menos gente: a
#   pergunta é da função (ContactPolicy#update?: no EE, `contact_manage`), então quem não alcança um não alcança nenhum.
# - Fica `fora` quem não recebe no WhatsApp: pediu para não receber, ou não tem celular válido
#   (ConversationAudience::Reach.phone). Quem só tem e-mail fica de fora: a campanha é de WhatsApp.
class Autonomia::Automacao::ContatosDaExecucao
  # Só o passo que cria num gatilho da conta, o único em que a campanha dispara: o "card" pede alvo
  # (ProblemasDoGatilho) e nunca salvaria antes dela. `prospeccao` chega com a G21 (#2706); até lá o esquema não tem esse
  # passo, e nenhuma receita com `publico: desta_execucao` salva.
  TIPOS_QUE_CRIAM = %w[prospeccao].freeze
  CHAVES_DE_CONTATO = %w[contato_id contato_ids].freeze
  CHAVES_DE_CARD = %w[card_id card_ids].freeze

  def initialize(execucao:)
    @execucao = execucao
    @conta = execucao.account
  end

  # Os contatos que entram no Público, em ordem de id.
  def dentro = recebem.first

  # Quantos ficaram de fora por não receber no WhatsApp.
  def fora = recebem.last.size

  # Os contatos que quem ligou não alcança.
  def sem_alcance = alcancados.last

  private

  def alcancados = (@alcancados ||= todos.partition { |contato| acesso.alcanca?(contato) })

  def recebem = (@recebem ||= alcancados.first.partition { |contato| recebe_no_whatsapp?(contato) })

  def recebe_no_whatsapp?(contato) = !contato.opted_out? && ::ConversationAudience::Reach.phone(contato).present?

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

  def acesso = (@acesso ||= ::Autonomia::Automacao::Acesso.new(@execucao.dona))
end
