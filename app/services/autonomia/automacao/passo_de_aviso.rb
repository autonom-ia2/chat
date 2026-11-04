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

    negado = sem_acesso
    return negado if negado

    texto = texto_pronto
    return Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {}) if texto.nil?

    avisar(texto)
  end

  # Com o texto já pronto. O "resumir" da F7 (#2500) chega aqui com o resumo da IA.
  def avisar(texto)
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: {}) if texto.strip.empty?

    pessoas, fora = destinatarios
    return Resultado.new(tipo: :pulado, motivo: 'ninguem_para_avisar', dados: { 'fora' => fora }) if pessoas.empty?

    nota = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => nota.id, 'pessoas' => pessoas.map(&:id), 'fora' => fora })
  end

  # O que pula sem olhar o texto: o "resumir" confere antes de pagar a IA.
  def ninguem_para_avisar
    pessoas, fora = destinatarios
    Resultado.new(tipo: :pulado, motivo: 'ninguem_para_avisar', dados: { 'fora' => fora }) if pessoas.empty?
  end

  private

  # Quem recebe e quem saiu, cada um com o motivo: não é da conta, não enxerga a conversa, ou enxerga mas a menção não
  # o avisaria (só administrador e membro da caixa recebem o aviso da menção).
  def destinatarios
    pedidos = ids.compact.uniq
    da_conta = @conversa.account.users.where(id: pedidos).to_a
    avisaveis = ::Autonomia::Automacao::Nota.avisaveis_ids(@conversa)
    avaliadas = da_conta.map { |pessoa| [pessoa, motivo_de_fora(pessoa, avisaveis)] }
    fora = avaliadas.filter_map { |pessoa, motivo| { 'id' => pessoa.id, 'motivo' => motivo } if motivo }
    [avaliadas.filter_map { |pessoa, motivo| pessoa unless motivo }, fora_da_conta(pedidos, da_conta) + fora]
  end

  def fora_da_conta(pedidos, da_conta)
    (pedidos - da_conta.map(&:id)).map { |id| { 'id' => id, 'motivo' => 'fora_da_conta' } }
  end

  def motivo_de_fora(pessoa, avisaveis)
    return 'nao_ve_a_conversa' unless ::Autonomia::Automacao::Acesso.alcanca?(pessoa, @conversa)

    'nao_e_da_caixa' unless avisaveis.include?(pessoa.id)
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
