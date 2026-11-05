# O passo "avisar" (#2414 F4): avisa a equipe, nunca o cliente. Vira uma nota privada na conversa que menciona cada
# pessoa (Nota): o sino, o push e o e-mail são os da menção, pela preferência de cada uma. Nunca menciona o time
# inteiro: só pessoas, conferidas uma a uma.
#
# Para quem: o responsável da conversa, os times (aberto pessoa a pessoa) e as pessoas escolhidas, só da conta. Fica
# só quem enxerga a conversa (D5), perguntado à política da conversa para cada pessoa: função personalizada e
# administrador mudam a resposta, e não basta estar na caixa. Quem não enxerga sai, com o motivo no registro
# (`fora`), e a lista vazia pula o passo. O texto, com os valores, só chega a quem passou. No card, é a conversa
# principal dele (NaConversa).
#
# Reserva (#2552): com `se_nao_houver: caixa`, quando a conversa não tem responsável ou ele não pode ser avisado (caiu
# no `fora`), entram os membros da caixa da conversa (só eles: administrador fora da caixa não entra), cada um pela
# mesma conferência. O ok diz qual dos dois aconteceu (caixa_sem_responsavel, caixa_responsavel_fora); a caixa sem
# ninguém avisável pula com caixa_sem_ninguem. A lista se soma: times e pessoas marcados são avisados de todo jeito.
#
# Só o responsável, sem a reserva, numa conversa sem responsável (#2523): o motivo é `sem_responsavel`, e o histórico e
# o ensaio dizem "ninguém foi avisado: a conversa não tem responsável", em vez de "ninguém na lista".
class Autonomia::Automacao::PassoDeAviso
  include ::Autonomia::Automacao::NaConversa

  CAIXA = 'caixa'.freeze

  # A reserva só vale junto do responsável (a Receita também barra), aqui e no ensaio.
  def self.reserva?(para)
    para = para.to_h
    para['responsavel'] == true && para['se_nao_houver'] == CAIXA
  end

  def self.sem_responsavel?(para, responsavel_id)
    para = para.to_h
    para['responsavel'] == true && para['se_nao_houver'].nil? && responsavel_id.nil? &&
      Array(para['times']).empty? && Array(para['pessoas']).empty?
  end

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

    pessoas, fora, reserva = destinatarios
    return Resultado.new(tipo: :pulado, motivo: motivo_sem_ninguem(reserva), dados: { 'fora' => fora }) if pessoas.empty?

    nota = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
    Resultado.new(tipo: :ok, motivo: reserva && "caixa_#{reserva}",
                  dados: { 'mensagem_id' => nota.id, 'pessoas' => pessoas.map(&:id), 'fora' => fora })
  end

  # O que pula sem olhar o texto: o "resumir" confere antes de pagar a IA.
  def ninguem_para_avisar
    pessoas, fora, reserva = destinatarios
    Resultado.new(tipo: :pulado, motivo: motivo_sem_ninguem(reserva), dados: { 'fora' => fora }) if pessoas.empty?
  end

  # Só lê, para o ensaio (#2498): com a reserva, o que o motor faria nesta conversa. nil quando o responsável seria
  # avisado; senão o motivo do registro sem o prefixo (sem_responsavel, responsavel_fora) ou caixa_sem_ninguem.
  def reserva_prevista
    pessoas, _fora, reserva = destinatarios
    pessoas.empty? ? 'caixa_sem_ninguem' : reserva
  end

  private

  def para = @passo['para'].to_h

  def motivo_sem_ninguem(reserva)
    return 'caixa_sem_ninguem' if reserva
    return 'sem_responsavel' if self.class.sem_responsavel?(para, @conversa.assignee_id)

    'ninguem_para_avisar'
  end

  # Quem recebe, quem saiu (cada um com o motivo) e, quando a caixa entrou de reserva, por quê: sem_responsavel ou
  # responsavel_fora. Saem quem não é da conta, quem não enxerga a conversa e quem enxerga mas a menção não o avisaria
  # (só administrador e membro da caixa recebem o aviso da menção). Uma conta por passo: o "resumir" pergunta antes e
  # depois da IA.
  def destinatarios
    @destinatarios ||= begin
      avisaveis = ::Autonomia::Automacao::Nota.avisaveis_ids(@conversa)
      pedidos = ids.compact.uniq
      pessoas, fora = conferir(pedidos, avisaveis)
      reserva = motivo_da_reserva(fora)
      if reserva
        # Quem já foi conferido (avisado ou de fora) não passa de novo.
        da_caixa, fora_da_caixa = conferir(@conversa.inbox.members.pluck(:id) - pedidos, avisaveis)
        # A caixa sem ninguém avisável só vira motivo quando ninguém mais foi avisado (caixa_sem_ninguem).
        [pessoas + da_caixa, fora + fora_da_caixa, (reserva if da_caixa.any? || pessoas.empty?)]
      else
        [pessoas, fora, nil]
      end
    end
  end

  def conferir(pedidos, avisaveis)
    da_conta = @conversa.account.users.where(id: pedidos).to_a
    vinculos = @conversa.account.account_users.where(user_id: da_conta.map(&:id)).index_by(&:user_id)
    avaliadas = da_conta.map { |pessoa| [pessoa, motivo_de_fora(pessoa, vinculos[pessoa.id], avisaveis)] }
    fora = avaliadas.filter_map { |pessoa, motivo| { 'id' => pessoa.id, 'motivo' => motivo } if motivo }
    [avaliadas.filter_map { |pessoa, motivo| pessoa unless motivo }, fora_da_conta(pedidos, da_conta) + fora]
  end

  def motivo_da_reserva(fora)
    return unless self.class.reserva?(para)
    return 'sem_responsavel' if @conversa.assignee_id.nil?

    'responsavel_fora' if fora.any? { |item| item['id'] == @conversa.assignee_id }
  end

  def fora_da_conta(pedidos, da_conta)
    (pedidos - da_conta.map(&:id)).map { |id| { 'id' => id, 'motivo' => 'fora_da_conta' } }
  end

  def motivo_de_fora(pessoa, vinculo, avisaveis)
    return 'nao_ve_a_conversa' unless ::Autonomia::Automacao::Acesso.alcanca?(pessoa, @conversa, account_user: vinculo)

    'nao_e_da_caixa' unless avisaveis.include?(pessoa.id)
  end

  def ids
    times = Array(para['times'])
    [
      (@conversa.assignee_id if para['responsavel']),
      *(times.any? ? TeamMember.joins(:team).where(teams: { account_id: @conversa.account_id, id: times }).pluck(:user_id) : []),
      *Array(para['pessoas'])
    ]
  end
end
