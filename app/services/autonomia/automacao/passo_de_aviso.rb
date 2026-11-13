# O passo "avisar" (#2414 F4): avisa a equipe, nunca o cliente. Vira uma nota privada na conversa que menciona cada
# pessoa (Nota): o sino, o push e o e-mail são os da menção, pela preferência de cada uma. Nunca menciona o time
# inteiro: só pessoas, conferidas uma a uma.
#
# Para quem: o responsável da conversa (G41: com a agente de IA atendendo, o dono do card da conversa, o "Responsável"
# do CRM; sem card ou sem dono, ninguém, e o passo pula com `sem_responsavel`), os times (aberto pessoa a pessoa), as
# pessoas escolhidas, quem atende a reunião (a pessoa da página de agendamento, ou quem marcou na tela): nos gatilhos
# de reunião (G32), a do gatilho; nos outros (G61), a próxima reunião marcada do contato; e, nos gatilhos de card, quem
# cuida do card (G9, #2707: a nova dona depois da troca na Lista do CRM, que nem sempre atende a conversa), só da conta. Fica
# só quem enxerga a conversa (D5), perguntado à política da conversa para cada pessoa: função personalizada e
# administrador mudam a resposta, e não basta estar na caixa. Quem não enxerga sai, com o motivo no registro
# (`fora`), e a lista vazia pula o passo. O texto, com os valores, só chega a quem passou. No card, é a conversa
# principal dele (NaConversa).
#
# Reserva (#2552): com `se_nao_houver: caixa`, quando a conversa não tem responsável (nem o dono do card, G41) ou ele
# não pode ser avisado (caiu no `fora`), entram os membros da caixa da conversa (só eles: administrador fora da caixa
# não entra), cada um pela mesma conferência. O ok diz qual dos dois aconteceu (caixa_sem_responsavel, caixa_responsavel_fora); a caixa sem
# ninguém avisável pula com caixa_sem_ninguem. A lista se soma: times e pessoas marcados são avisados de todo jeito.
#
# Só o responsável, sem a reserva, numa conversa sem responsável (#2523): o motivo é `sem_responsavel`, e o histórico e
# o ensaio dizem "ninguém foi avisado: a conversa não tem responsável", em vez de "ninguém na lista".
class Autonomia::Automacao::PassoDeAviso
  include ::Autonomia::Automacao::NaConversa

  SEM_RESPONSAVEL = { 'id' => nil, 'motivo' => 'sem_responsavel' }.freeze
  CAIXA = 'caixa'.freeze

  # A reserva só vale junto do responsável (a Receita também barra), aqui e no ensaio.
  def self.reserva?(para)
    para = para.to_h
    para['responsavel'] == true && para['se_nao_houver'] == CAIXA
  end

  # Só o responsável foi pedido, sem a reserva, e ele não existe: ninguém seria avisado (#2523).
  def self.sem_responsavel?(para, responsavel_id)
    para = para.to_h
    para['responsavel'] == true && para['se_nao_houver'].nil? && responsavel_id.nil? &&
      Array(para['times']).empty? && Array(para['pessoas']).empty? && !para['da_reuniao'] && !para['responsavel_do_card']
  end

  # O ensaio (#2498) do "avisar", e do "resumir" que sai por ele: a mesma conta do motor, que só lê (#previsto). Os
  # outros passos não avisam ninguém.
  def self.ensaiar(passo, conversa)
    para = para_do_aviso(passo)
    return [] if para.nil?

    new(execucao: nil, passo: { 'id' => passo['id'], 'para' => para }, alvo: conversa).previsto
  end

  # Como o motor monta o aviso do resumir (PassoDeResumir#passo_do_aviso).
  def self.para_do_aviso(passo)
    return passo['para'].to_h if passo['tipo'] == 'avisar'

    passo.dig('destino', 'avisar').to_h if passo['tipo'] == 'resumir' && passo['destino'].is_a?(Hash)
  end

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

    pessoas, fora, reserva = destinatarios
    return Resultado.new(tipo: :pulado, motivo: motivo_do_pulo(fora, reserva), dados: { 'fora' => fora }) if pessoas.empty?

    nota = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
    Resultado.new(tipo: :ok, motivo: reserva && "caixa_#{reserva}",
                  dados: { 'mensagem_id' => nota.id, 'pessoas' => pessoas.map(&:id), 'fora' => fora })
  end

  # O que pula sem olhar o texto: o "resumir" confere antes de pagar a IA.
  def ninguem_para_avisar
    pessoas, fora, reserva = destinatarios
    Resultado.new(tipo: :pulado, motivo: motivo_do_pulo(fora, reserva), dados: { 'fora' => fora }) if pessoas.empty?
  end

  # Só lê, para o ensaio (#2498), que não tem execução: o que o motor faria nesta conversa, como [por que ninguém seria
  # avisado, por que iria para a caixa]. Ninguém: sem_responsavel (#2523) ou, com a reserva, caixa_sem_ninguem. Caixa:
  # sem_responsavel ou responsavel_fora. Sem a execução, quem atende a reunião e quem cuida do card não entram na conta.
  def previsto
    return ['sem_responsavel', nil] if self.class.sem_responsavel?(para, responsavel_id)
    return [nil, nil] unless self.class.reserva?(para)

    pessoas, _fora, reserva = destinatarios
    pessoas.empty? ? ['caixa_sem_ninguem', nil] : [nil, reserva]
  end

  private

  def para = @passo['para'].to_h

  def motivo_do_pulo(fora, reserva)
    return 'caixa_sem_ninguem' if reserva
    return 'sem_responsavel' if fora.include?(SEM_RESPONSAVEL) || self.class.sem_responsavel?(para, responsavel_id)

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
      fora = sem_responsavel + fora
      reserva = motivo_da_reserva(fora)
      reserva ? com_a_caixa(pedidos, avisaveis, pessoas, fora, reserva) : [pessoas, fora, nil]
    end
  end

  # Quem já foi conferido (avisado ou de fora) não passa de novo. A caixa sem ninguém avisável só vira motivo quando
  # ninguém mais foi avisado (caixa_sem_ninguem).
  def com_a_caixa(pedidos, avisaveis, pessoas, fora, reserva)
    da_caixa, fora_da_caixa = conferir(@conversa.inbox.members.pluck(:id) - pedidos, avisaveis)
    [pessoas + da_caixa, fora + fora_da_caixa, (reserva if da_caixa.any? || pessoas.empty?)]
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
    return 'sem_responsavel' if responsavel_id.nil?

    'responsavel_fora' if fora.any? { |item| item['id'] == responsavel_id }
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
      (responsavel_id if para['responsavel']),
      *(times.any? ? TeamMember.joins(:team).where(teams: { account_id: @conversa.account_id, id: times }).pluck(:user_id) : []),
      *Array(para['pessoas']),
      (quem_atende if para['da_reuniao'] && @execucao),
      (dono_do_card if para['responsavel_do_card'] && @execucao)
    ]
  end

  # A pessoa que atende a conversa; com a agente de IA atendendo, o dono do card dela (G41). Lido uma vez por passo.
  def responsavel_id
    return @responsavel_id if defined?(@responsavel_id)

    @responsavel_id = agente_de_ia_atende? ? card_atendido&.owner_id : @conversa.assignee_id
  end

  def card_atendido = @alvo.is_a?(::Crm::Card) ? @alvo : card_da_conversa

  def agente_de_ia_atende? = @conversa.assignee_id.nil? && @conversa.ai_assignee.present?

  def card_da_conversa
    return unless ::Crm::Config.enabled?

    ::Crm::Cards::ConversationCardFinder.new(account: @conversa.account).find(@conversa)
  end

  def sem_responsavel
    para['responsavel'] && agente_de_ia_atende? && responsavel_id.nil? ? [SEM_RESPONSAVEL] : []
  end

  # Quem atende a reunião: na marcada pela página, o agente do link ou a pessoa padrão da página; na marcada na tela, quem
  # marcou (Crm::Meetings::Creator grava em created_by). Nos gatilhos de reunião, a do gatilho. Nos outros (G61, exemplo
  # 6, passo 6: "Marcou: avisa a profissional"), a próxima reunião marcada do contato, só em card que quem ligou vê.
  # Sem reunião, ninguém. Pelo alvo da execução: o "resumir" chama este passo com a conversa, e a reunião é do card.
  def quem_atende
    contexto = ::Autonomia::Automacao::Contexto.de(@execucao.alvo, execucao: @execucao)
    return contexto.reuniao&.created_by_id if ::Autonomia::Automacao::Gatilhos.de_reuniao?(@execucao.chave_gatilho)

    ::Autonomia::Automacao::ValoresDaReuniao.proxima_do_contato(contexto.contato, @execucao.dona.ligada_por)&.created_by_id
  end

  # Quem cuida do card da execução, lido na hora do passo. Pelo alvo da execução, como a reunião: o "resumir" chama este
  # passo com a conversa. Sem card, ninguém.
  def dono_do_card = ::Autonomia::Automacao::Contexto.de(@execucao.alvo, execucao: @execucao).card&.owner_id
end
