# G42 (#2721, exemplo 1, passo 12): o que a própria execução mandou ao cliente, para o "resumir" contar tudo o que foi
# tentado: o modelo no WhatsApp, o e-mail (que abre uma conversa própria, G34) e as respostas que vieram nessas conversas.
#
# - Os envios saem dos registros da execução (`mensagem_id`, a mesma ponte do histórico): só mensagem ao cliente, de
#   saída e não privada. A nota do "avisar" fica de fora. O texto do envio é o da receita e vai com a marca
#   `not_delivered` quando o canal recusou (status failed).
# - Só entra conversa que quem ligou a automação vê (Acesso.alcanca?, a política da conversa, só leitura). Outras
#   conversas do contato, que a execução não tocou, não entram.
# - As respostas das outras conversas (`other_conversations`) vão para a nota ou o aviso, que ficam na conversa do alvo:
#   qualquer pessoa que abre essa conversa lê o resumo (pareceres de Funções e Qualidade no #2763). Então a outra conversa
#   só entra se toda pessoa da conta que vê a conversa do alvo também a vê (a mesma política, com caixa, time e função).
#   As que ficam de fora vão em `fora` (os ids), e o histórico diz quantas.
# - A conversa do alvo já vai na leitura do passo. Das outras, a mesma leitura de mensagens do passo (o Estado).
# - G68 (#2864): o "extrair" usa a mesma leitura; com `fuso`, cada mensagem das outras conversas vai com a data e a hora.
class Autonomia::Automacao::EnviosDaExecucao
  LEITURAS_DE_MENSAGEM = %w[mensagens_recentes mensagens_com_respostas ultima_mensagem].freeze
  MAX_CARACTERES = ::Autonomia::Decisores::Estado::MAX_CARACTERES

  def initialize(execucao:, conversa:, leituras:, fuso: nil)
    @execucao = execucao
    @conversa = conversa
    @leituras = Array(leituras) & LEITURAS_DE_MENSAGEM
    @fuso = fuso
  end

  # O que vai à IA junto da leitura do passo. Vazio quando a execução ainda não mandou nada.
  def dados
    @dados ||= { automation_sends: envios.map { |mensagem| envio(mensagem) },
                 other_conversations: lidas.map { |conversa| leitura(conversa) }.compact_blank }.compact_blank
  end

  # Leu resposta de outra conversa: o resumo não fica para reuso (ia.<passo>), que o levaria a outro lugar.
  def outras_lidas? = dados.key?(:other_conversations)

  # Os ids das outras conversas que nem todos que veem a conversa do alvo veem, para o histórico.
  def fora = (outras - lidas).map(&:display_id)

  private

  def mensagens
    @mensagens ||= begin
      ids = @execucao.registros.where(resultado: 'ok').pluck(:dados).filter_map { |dados| dados.to_h['mensagem_id'] }
      Message.where(id: ids, account_id: @execucao.account_id, private: false, message_type: :outgoing)
             .includes(conversation: :inbox).reorder(:id).to_a
    end
  end

  def visiveis
    @visiveis ||= mensagens.map(&:conversation).uniq.select { |conversa| conversa == @conversa || ve?(quem_ligou, conversa) }
  end

  def quem_ligou = @execucao.automacao.ligada_por

  def ve?(pessoa, conversa) = pessoa.present? && ::Autonomia::Automacao::Acesso.alcanca?(pessoa, conversa)

  def envios = mensagens.select { |mensagem| visiveis.include?(mensagem.conversation) }

  def outras = visiveis - [@conversa]

  def lidas
    @lidas ||= outras.select { |conversa| quem_ve_o_alvo.all? { |membro| membro_ve?(membro, conversa) } }
  end

  def quem_ve_o_alvo
    @quem_ve_o_alvo ||= outras.empty? ? [] : @conversa.account.account_users.includes(:user).select { |membro| membro_ve?(membro, @conversa) }
  end

  # A leitura da conversa (ConversationPolicy#view?), com o vínculo da pessoa já lido: quem só lê (conversation_view, no EE)
  # também abre a conversa do alvo e lê o resumo, então conta em "quem vê o alvo" (parecer de Funções no #2876). No OSS,
  # view? é o mesmo que show?. Quem não é administrador só alcança pela caixa ou pelo time, nas duas perguntas: quem não
  # está em nenhum dos dois nem chega à política. Os membros das caixas e dos times saem numa leitura para todas as
  # conversas, não uma por pessoa e conversa.
  def membro_ve?(membro, conversa)
    return false unless membro.administrator? || na_caixa_ou_no_time?(membro.user_id, conversa)

    ConversationPolicy.new({ user: membro.user, account: @conversa.account, account_user: membro }, conversa).view?
  end

  def na_caixa_ou_no_time?(user_id, conversa)
    membros_das_caixas[conversa.inbox_id].to_a.include?(user_id) || membros_dos_times[conversa.team_id].to_a.include?(user_id)
  end

  def membros_das_caixas
    @membros_das_caixas ||= agrupados(InboxMember.where(inbox_id: [@conversa, *outras].map(&:inbox_id)).pluck(:inbox_id, :user_id))
  end

  def membros_dos_times
    @membros_dos_times ||= agrupados(TeamMember.where(team_id: [@conversa, *outras].filter_map(&:team_id)).pluck(:team_id, :user_id))
  end

  def agrupados(pares) = pares.group_by(&:first).transform_values { |lista| lista.map(&:last) }

  def envio(mensagem)
    conversa = mensagem.conversation
    { channel: conversa.inbox&.channel_type.to_s.demodulize.underscore.presence,
      subject: conversa.additional_attributes.to_h['mail_subject'].to_s.strip.first(300).presence,
      text: mensagem.content.to_s.strip.first(MAX_CARACTERES), not_delivered: (true if mensagem.failed?) }.compact
  end

  def leitura(conversa)
    leituras = @leituras.presence || ::Autonomia::Decisor::LEITURAS_PADRAO
    ::Autonomia::Decisores::Estado.new(conversation: conversa, leituras: leituras, fuso: @fuso).conversa
  end
end
