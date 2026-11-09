# card.sem_documento (G46, exemplo 14, passo 5: "2 dias sem documento novo: lembra uma vez"): o card aberto na etapa
# escolhida há `dias` dias sem o cliente mandar documento. A conta começa na entrada na etapa e recomeça a cada
# documento que chega; texto e áudio ("já mando") não recomeçam.
#
# - Documento é foto (anexo de tipo imagem) ou PDF (anexo de tipo arquivo com o tipo application/pdf), como o termo diz
#   no passo 2 ("A cada foto ou PDF que chega"). Áudio, vídeo, local e outro arquivo (docx, zip) não contam. A figurinha
#   chega como imagem; a que vem marcada (`meta.is_sticker`, ConversaCanal::FigurinhaRecebida) não conta.
# - Só conta o documento do contato do card que chegou numa conversa que quem ligou vê: a régua do "cliente respondeu"
#   (Resposta.conversas_que_ve, #2680). Documento numa caixa que a pessoa não abre não decide nada.
# - `desde` é o mais recente entre a entrada na etapa e o último documento depois dela. Dispara quando `desde` cai na
#   janela do Parado: entre `dias + janela` e `dias` atrás, nunca antes de ligar menos `dias`. Ligar não age no
#   passado, e o que ficou mais de 1 dia sem varredura (uma pane) não roda depois.
# - A marca é o próprio `desde` (Gatilhos.marca_do_sem_documento): uma vez por silêncio. O documento seguinte muda o
#   `desde`, e o gatilho volta a contar.
# - Uma consulta só: o último documento é uma subconsulta por card candidato (aberto, na etapa, há pelo menos `dias`
#   dias nela), nunca uma ida ao banco por card. Só o horário do documento é lido; nada do conteúdo.
class Autonomia::Automacao::Tempo::SemDocumento
  PDF = 'application/pdf'.freeze
  DESDE = 'desde_do_documento'.freeze
  FIGURINHA = ::ConversaCanal::FigurinhaRecebida::CHAVE

  def initialize(definicao:, gatilho:, agora:)
    @definicao = definicao
    @gatilho = gatilho
    @agora = agora
  end

  # Cada card da janela, com a marca do silêncio.
  def cada
    escopo.find_each do |card|
      yield card, ::Autonomia::Automacao::Gatilhos.marca_do_sem_documento(card, card.public_send(DESDE))
    end
  end

  def escopo
    dias = @gatilho['dias'].to_i.days
    limite = @agora - dias
    inicio = [limite - ::Autonomia::Automacao::Tempo::JANELA, ::Autonomia::Automacao::Tempo.ligada_desde(@definicao) - dias].max
    ::Crm::Card.from(candidatos(limite), :crm_cards).select('crm_cards.*').where(DESDE => inicio..limite)
  end

  private

  def candidatos(limite)
    ::Crm::Card.where(account_id: @definicao.account_id, stage_id: @gatilho['etapa_id'], status: :open)
               .where(entered_stage_at: ..limite)
               .select("crm_cards.*, GREATEST(crm_cards.entered_stage_at, (#{ultimo_documento})) AS #{DESDE}")
  end

  # O instante do último documento do contato do card depois da entrada na etapa, nas conversas que quem ligou vê.
  # Sem quem ligou, a automação não roda (Acesso); aqui fica só a entrada na etapa.
  def ultimo_documento
    quem = @definicao.ligada_por
    return 'NULL' if quem.nil?

    ::Message.unscoped.incoming.where(account_id: @definicao.account_id)
             .joins(:conversation).where('conversations.contact_id = crm_cards.contact_id')
             .where(conversation_id: conversas_que_ve(quem).select(:id))
             .where('messages.created_at > crm_cards.entered_stage_at')
             .where(documento.arel.exists)
             .select('MAX(messages.created_at)').to_sql
  end

  def conversas_que_ve(quem)
    conta = @definicao.account
    ::Autonomia::Automacao::Resposta.conversas_que_ve(::Conversation.where(account_id: conta.id), quem, conta)
  end

  # Foto (sem a figurinha marcada) ou PDF, na mensagem da linha de fora.
  def documento
    da_mensagem = ::Attachment.where('attachments.message_id = messages.id')
    foto = da_mensagem.where(file_type: :image).where("COALESCE(attachments.meta ->> ?, 'false') <> 'true'", FIGURINHA)
    foto.or(da_mensagem.where(file_type: :file).where(pdf.arel.exists))
  end

  def pdf
    ::ActiveStorage::Attachment.where(record_type: 'Attachment', name: 'file')
                               .where('active_storage_attachments.record_id = attachments.id')
                               .joins(:blob).where(active_storage_blobs: { content_type: PDF })
  end
end
