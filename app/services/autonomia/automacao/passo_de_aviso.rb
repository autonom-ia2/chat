# O passo "avisar" (#2414 F4): avisa a equipe, nunca o cliente. Vira uma nota privada na conversa que menciona cada
# pessoa (Nota): o sino, o push e o e-mail são os da menção, pela preferência de cada uma. Nunca menciona o time
# inteiro: só pessoas, conferidas uma a uma.
#
# Para quem: o responsável da conversa, o responsável do card (G9, #2707: quem cuida do card não é sempre quem atende
# a conversa; lido do alvo da execução, porque o "resumir" entrega aqui com a conversa; sem card, ninguém), os times
# (aberto pessoa a pessoa) e as pessoas escolhidas, só da conta. Fica só quem enxerga a conversa (D5), perguntado à
# política da conversa para cada pessoa: função personalizada e administrador mudam a resposta, e não basta estar na
# caixa. Quem não enxerga sai, com o motivo no registro
# (`fora`), e a lista vazia pula o passo. O texto, com os valores, só chega a quem passou. No card, é a conversa
# principal dele (NaConversa).
class Autonomia::Automacao::PassoDeAviso
  include ::Autonomia::Automacao::NaConversa

  # Ao salvar: os times e as pessoas são da conta; "quem cuida do card" (G9) só com gatilho de card, porque fora dele o
  # aviso sairia para ninguém, calado. Vale para o "avisar" e para o aviso do "resumir".
  def self.problemas_ao_salvar(conta, passo, gatilho)
    para = passo['para'].to_h
    de_fora(passo['id'], :time_de_fora, Array(para['times']) - conta.teams.where(id: para['times']).pluck(:id)) +
      de_fora(passo['id'], :pessoa_de_fora, Array(para['pessoas']) - conta.users.where(id: para['pessoas']).pluck(:id)) +
      sem_card(passo['id'], para, gatilho)
  end

  def self.de_fora(id, chave, ids) = ids.map { |fora| problema(chave, passo: id, id: fora) }

  def self.sem_card(id, para, gatilho)
    return [] if !para['responsavel_do_card'] || ::Autonomia::Automacao::Gatilhos.alvo(gatilho) == ::Autonomia::Automacao::Gatilhos::CARD

    [problema(:responsavel_do_card_sem_card, passo: id)]
  end

  def self.problema(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def executar
    return sem_conversa if @conversa.nil?

    negado = sem_acesso
    return negado if negado

    texto = texto_pronto
    return faltou_valor if texto.nil?

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
      (::Autonomia::Automacao::Contexto.de(@execucao.alvo).card&.owner_id if para['responsavel_do_card']),
      *(times.any? ? TeamMember.joins(:team).where(teams: { account_id: @conversa.account_id, id: times }).pluck(:user_id) : []),
      *Array(para['pessoas'])
    ]
  end
end
