# O passo "avisar" (#2414 F4): avisa a equipe, nunca o cliente. Vira uma nota privada na conversa que menciona cada
# pessoa (Nota): o sino, o push e o e-mail são os da menção, pela preferência de cada uma. Nunca menciona o time
# inteiro: só pessoas, conferidas uma a uma.
#
# Para quem: o responsável da conversa, os times (aberto pessoa a pessoa) e as pessoas escolhidas, só da conta. Fica
# só quem enxerga a conversa (D5), perguntado à política da conversa para cada pessoa: função personalizada e
# administrador mudam a resposta, e não basta estar na caixa. Quem não enxerga sai, com o motivo no registro
# (`fora`), e a lista vazia pula o passo. O texto, com os valores, só chega a quem passou. No card, é a conversa
# principal dele (NaConversa).
class Autonomia::Automacao::PassoDeAviso
  include ::Autonomia::Automacao::NaConversa

  def executar
    return sem_conversa if @conversa.nil?

    texto = texto_pronto
    return Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {}) if texto.nil?
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: {}) if texto.strip.empty?

    pessoas, fora = destinatarios
    return Resultado.new(tipo: :pulado, motivo: 'ninguem_para_avisar', dados: { 'fora' => fora }) if pessoas.empty?

    nota = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => nota.id, 'pessoas' => pessoas.map(&:id), 'fora' => fora })
  end

  private

  # Quem recebe e quem saiu, cada um com o motivo: não é da conta, ou não enxerga a conversa.
  def destinatarios
    pedidos = ids.compact.uniq
    da_conta = @conversa.account.users.where(id: pedidos).to_a
    pessoas, sem_acesso = da_conta.partition { |pessoa| ::Autonomia::Automacao::Acesso.alcanca?(pessoa, @conversa) }
    fora = (pedidos - da_conta.map(&:id)).map { |id| { 'id' => id, 'motivo' => 'fora_da_conta' } } +
           sem_acesso.map { |pessoa| { 'id' => pessoa.id, 'motivo' => 'nao_ve_a_conversa' } }
    [pessoas, fora]
  end

  def ids
    para = @passo['para'].to_h
    times = Array(para['times'])
    [
      (@conversa.assignee_id if para['responsavel']),
      *(times.any? ? TeamMember.joins(:team).where(teams: { account_id: @conversa.account_id, id: times }).pluck(:user_id) : []),
      *Array(para['pessoas'])
    ]
  end
end
