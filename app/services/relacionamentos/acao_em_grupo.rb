# Uma ação em grupo da Lista nova de Relacionamentos (#2894): criar cards, etiquetar ou apagar as pessoas marcadas.
#
# Só mexe em pessoa da conta. A que não é (de outra conta, que nunca existiu ou que alguém apagou no meio do caminho,
# sem dizer qual) fica "de fora" como "não existe mais", sem nome, e não derruba o lote: repetir o pedido não trava.
# Depois faz a ação pessoa por pessoa, cada uma na própria transação: a que não deu fica "de fora" com o motivo em código
# e as outras seguem. Só falha de registro ou do banco vira "de fora"; erro de programa estoura, para não se disfarçar
# de resultado.
#
# Não há teto de pessoas (regra do dono do produto: nenhum freio no uso). A FATIA é só o tamanho de cada leitura de nomes.
class Relacionamentos::AcaoEmGrupo
  FATIA = 1_000
  NAO_EXISTE_MAIS = 'nao_existe_mais'.freeze
  DADOS_INVALIDOS = 'dados_invalidos'.freeze
  ERRO = 'erro'.freeze
  # #3062 — a pessoa já estava como o pedido quer (já tinha a etiqueta, ou não tinha a que era para tirar): não muda, não
  # conta como feita e não fica de fora. Assim o aviso diz quantas pessoas mudaram de verdade.
  SEM_MUDANCA = :sem_mudanca
  # Falha que é daquela pessoa naquele momento (trava, registro que não gravou ou não saiu). Consulta que o banco recusa
  # (ActiveRecord::StatementInvalid) é defeito de programa e estoura.
  FALHAS_DA_VEZ = [ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::RecordNotSaved,
                   ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordNotUnique].freeze

  def initialize(account:, user:, pessoa_ids:)
    @account = account
    @user = user
    @pessoa_ids = ids_de(pessoa_ids)
  end

  # { <contagem da ação> => quantas deram certo, de_fora: [{ id:, nome:, motivo: }] }
  def call
    nomes = nomes_das_pessoas
    preparar
    motivos = @pessoa_ids.index_with { |pessoa_id| nomes.key?(pessoa_id) ? tentar(pessoa_id) : NAO_EXISTE_MAIS }
    de_fora = motivos.filter_map do |pessoa_id, motivo|
      { id: pessoa_id, nome: nomes[pessoa_id], motivo: motivo } if motivo && motivo != SEM_MUDANCA
    end
    { contagem => motivos.values.count(&:nil?), :de_fora => de_fora }
  end

  private

  # O que vale para o pedido inteiro (funil, etapa, etiqueta): cada ação confere o seu e recusa antes de começar.
  def preparar; end

  def ids_de(valores)
    Array(valores).map { |valor| Integer(valor.to_s, 10, exception: false) || recusar('pessoa_ids em formato inválido') }.uniq
  end

  def nomes_das_pessoas
    recusar('escolha pelo menos uma pessoa') if @pessoa_ids.empty?

    @pessoa_ids.each_slice(FATIA).flat_map { |ids| @account.contacts.where(id: ids).pluck(:id, :name) }.to_h
  end

  # O motivo de a pessoa ficar de fora, SEM_MUDANCA quando ela já estava como o pedido quer, ou nil quando deu certo.
  def tentar(pessoa_id)
    fazer(pessoa_id)
  rescue ActiveRecord::RecordNotFound
    NAO_EXISTE_MAIS
  rescue ActiveRecord::RecordInvalid
    DADOS_INVALIDOS
  rescue *FALHAS_DA_VEZ => e
    Rails.logger.error("[relacionamentos.acao_em_grupo] #{self.class.name} pessoa=#{pessoa_id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account, user: @user).capture_exception
    ERRO
  end

  def recusar(mensagem)
    raise Relacionamentos::PedidoInvalido, mensagem
  end
end
