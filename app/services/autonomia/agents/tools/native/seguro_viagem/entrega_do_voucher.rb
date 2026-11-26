# O VOUCHER EM PDF COMO CARTÃO DO TURNO (#3246), no mesmo caminho do comparativo (`EntregaDoComparativo`):
# `situacao_do_pagamento` (pagamento feito, voucher ainda não enviado nesta cotação) e `segunda_via_do_voucher` só marcam
# o cartão (`cartao`); o `Operate::CartoesDoTurno` o posta depois da resposta do turno, com o token e os descartes de
# sempre. Com responsável na conversa vira nota privada, como o comparativo.
#
# EM DUAS METADES, para a rede ficar fora do lock da conversa (`CartoesDoTurno#voucher!`):
#   - `baixar`, sem lock: pede à Universal a URL do PDF (`url_do_voucher`, pelo carrinho da proposta guardada) e baixa o
#     PDF com `Tools::EntregaDeArquivo` (só https, sem redirecionamento, assinatura `%PDF-`, até 10 MB), que já o grava
#     no armazenamento. A URL leva o token do carrinho: nunca vai a log.
#   - `criar`, sob o lock: anexa o PDF numa mensagem sem texto e, quando ela vai ao cliente (pública), grava
#     `voucher_enviado_em` na proposta, sob o lock da cotação (a ordem dos locks é conversa, depois cotação; a proposta
#     e a situação do pagamento só travam a cotação). A nota privada (há responsável) não chegou ao cliente: o próximo
#     "pago" ainda manda o voucher.
#
# SÓ DA UNIVERSAL: a URL do PDF só é baixada com o host `universal-assistance.com` ou um subdomínio dele.
#
# UM VOUCHER POR COTAÇÃO ENTRE TURNOS QUE CORREM JUNTOS (`saiu_depois?`): dois turnos que viram "pago" antes de o
# primeiro voucher sair marcam um cartão cada. O segundo não sai se já há, depois da âncora dele, um voucher da mesma
# cotação (de outro cartão). A segunda via de um turno seguinte sai: a âncora dela é mais nova que o voucher anterior.
#
# O BLOB LEVA DADO PESSOAL e é gravado antes da mensagem, fora de uma execução: vai com a finalidade `FINALIDADE`, e o
# varredor apaga o que ficou sem mensagem (`blobs_sem_mensagem`, `ReapStaleRunsJob`).
#
# A FALHA NÃO FALA COM O CLIENTE. A Universal fora, o acesso recusado, o voucher não encontrado, a URL que responde outra
# coisa que não PDF (o JSON de "pagamento ainda não realizado") ou o armazenamento fora: uma nota PRIVADA para a equipe
# (uma por cartão) e um log só com ids e o código da falha. O PDF leva CPF, endereço e nascimento: só vai à conversa do
# próprio cliente, nunca a log.
class Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Arquivo = Autonomia::Agents::Tools::EntregaDeArquivo
  TIPO_DO_CARTAO = 'voucher_viagem'.freeze
  CHAVE = 'autonomia_voucher_viagem'.freeze
  NOME_DO_ARQUIVO = 'voucher-seguro-viagem.pdf'.freeze
  # O motivo do cartão que não saiu, para o `EnviarCartoesJob` (`cartao_nao_enviado`).
  NAO_SAIU = 'voucher_nao_saiu'.freeze
  NOTA = 'autonomia.contratados.universal.notas.voucher_nao_saiu'.freeze
  # O motivo do cartão que não sai porque outro turno já mandou o voucher desta cotação (`saiu_depois?`).
  JA_SAIU = 'voucher_ja_saiu'.freeze
  # A guarda de `postar_com_guarda` diz que este cartão já saiu: nada a fazer, e não é motivo de descarte.
  POSTADO = :postado
  FALHAS = [Autonomia::Seguradoras::Universal::Cliente::Erro, Arquivo::Indisponivel].freeze
  FINALIDADE = 'voucher_do_turno'.freeze
  HOST_DA_UNIVERSAL = 'universal-assistance.com'.freeze
  # A chave da proposta com o turno que marcou o cartão do voucher por último (`marcar`).
  MARCADO_NO_TURNO = 'voucher_marcado_no_turno'.freeze

  def self.cartao(cotacao)
    { 'tipo' => TIPO_DO_CARTAO, 'chave' => cotacao.id.to_s, 'rich_message' => nil }
  end

  # Marca o cartão do voucher no turno e grava na proposta QUAL turno o marcou (`MARCADO_NO_TURNO`, o `Delivery#turno`),
  # sob o lock da cotação. É o que o aviso automático do pagamento (`Tools::EventoDaViagem`) confere, na hora de postar,
  # para não mandar um segundo "confirmado" e um segundo PDF quando o turno do cliente já marcou o voucher e ele ainda
  # não saiu (`voucher_enviado_em` só é gravado quando o PDF sai). O próprio turno do aviso grava a marca dele, e ela não
  # o cala. Proposta nova (outro carrinho) substitui a guardada inteira: a marca vai junto.
  def self.marcar(delivery, cotacao)
    cotacao.with_lock { cotacao.update!(proposta: cotacao.proposta.to_h.merge(MARCADO_NO_TURNO => delivery.turno)) }
    delivery.marcar_cartao(cartao(cotacao))
  end

  def self.cartao?(cartao)
    cartao.to_h['tipo'] == TIPO_DO_CARTAO
  end

  # A cotação do cartão, só desta conversa; nil quando ela não existe mais.
  def self.cotacao_do(cartao, conversation)
    Autonomia::Agents::CotacaoDeViagem.find_by(id: cartao['chave'].to_i, conversation_id: conversation.id)
  end

  # Já saiu, depois da âncora `ancora_id`, um voucher desta cotação por OUTRO cartão (`token` é o deste)? O `LIKE` é a
  # peneira; quem decide é o atributo.
  def self.saiu_depois?(conversation, cotacao_id:, ancora_id:, token:)
    conversation.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', ancora_id)
                .where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                .any? do |message|
                  atributos = message.content_attributes.to_h
                  atributos[CHAVE].to_s == cotacao_id.to_s && atributos['autonomia_cartao_token'].to_s != token.to_s
                end
  end

  # Os blobs de voucher sem mensagem, criados antes de `antes_de`: o processo morreu entre o blob e a mensagem. A
  # finalidade é lida como JSON, no nível superior do `metadata` (`EntregaDeArquivo::METADATA_JSON_SQL`).
  def self.blobs_sem_mensagem(antes_de:, limite:)
    ActiveStorage::Blob.unattached.where(created_at: ...antes_de)
                       .where("#{Arquivo::METADATA_JSON_SQL} ->> :chave = :finalidade", chave: Arquivo::FINALIDADE_CHAVE,
                                                                                        finalidade: FINALIDADE)
                       .order(:created_at).limit(limite)
  end

  # `atributos`: o que o cartão grava na mensagem (o agente e o token do turno).
  def initialize(conversation:, cotacao:, sender_id:, atributos:)
    @conversation = conversation
    @cotacao = cotacao
    @sender_id = sender_id
    @atributos = atributos
  end

  # Quem chama é o `CartoesDoTurno#postar!`. A guarda (bloco) devolve o motivo de não postar, `POSTADO` ou nil; é
  # conferida antes do download, sem lock (para não baixar à toa), e de novo sob o lock da conversa. -> nil quando
  # postou (ou o cartão já tinha saído); senão o motivo. O PDF que não virou mensagem (a guarda mudou durante o
  # download, erro ao criar) vai para a limpeza.
  def postar_com_guarda(&guarda)
    impedimento = yield
    return motivo(impedimento) if impedimento

    blob = baixar
    blob.nil? ? NAO_SAIU : anexar(blob, guarda)
  end

  # FORA do lock da conversa. -> o `ActiveStorage::Blob` do PDF, já gravado; nil quando o voucher não saiu (a nota da
  # equipe já foi postada).
  def baixar
    return nao_saiu('sem_acesso') unless @cotacao.agent.acesso_da_seguradora&.ok?

    arquivo = arquivo_da_universal
    defeito = arquivo.defeito || ('host' unless da_universal?(arquivo.url))
    return nao_saiu("forma_#{defeito}") if defeito

    arquivo.gravar(run_id: nil, finalidade: FINALIDADE)
  rescue *FALHAS => e
    nao_saiu(codigo_da(e))
  end

  # SOB o lock da conversa (quem chama já conferiu as guardas). -> a mensagem com o PDF.
  def criar(blob)
    mensagem = Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: nil, attachments: [blob.signed_id], message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @sender_id, private: @conversation.assignee_id.present?,
        content_attributes: @atributos.merge(CHAVE => @cotacao.id)
      )
    ).perform
    marcar_enviado unless mensagem.private
    mensagem
  end

  private

  def anexar(blob, guarda)
    anexado = nil
    impedimento = @conversation.with_lock do
      sob_lock = guarda.call
      anexado = criar(blob) unless sob_lock
      sob_lock
    end
    motivo(impedimento)
  ensure
    Arquivo.agendar_limpeza(blob, contexto: 'voucher') if anexado.nil?
  end

  def motivo(impedimento)
    impedimento == POSTADO ? nil : impedimento
  end

  def arquivo_da_universal
    resposta = SeguroViagem::Pagamento.cliente(@cotacao.agent).url_do_voucher(SeguroViagem::Pagamento.carrinho(@cotacao))
    Arquivo.new(url: resposta.is_a?(Hash) ? resposta['url'] : nil, nome: NOME_DO_ARQUIVO)
  end

  def codigo_da(erro)
    erro.is_a?(Arquivo::Indisponivel) ? erro.motivo : erro.codigo
  end

  def da_universal?(url)
    host = URI.parse(url).host.to_s.downcase
    host == HOST_DA_UNIVERSAL || host.end_with?(".#{HOST_DA_UNIVERSAL}")
  rescue URI::InvalidURIError
    false
  end

  def marcar_enviado
    @cotacao.with_lock do
      @cotacao.update!(proposta: @cotacao.proposta.to_h.merge('voucher_enviado_em' => Time.current.iso8601))
    end
  end

  # -> nil. `falha` é um código curto e fechado (o do cliente HTTP ou o da entrega de arquivo), nunca a URL nem o corpo.
  def nao_saiu(falha)
    Rails.logger.warn("[autonomia][seguro_viagem] voucher_nao_saiu conv=#{@conversation.id} cotacao=#{@cotacao.id} falha=#{falha}")
    Autonomia::Insurance::NotaNaHora.postar(@conversation, I18n.t(NOTA),
                                            chave: "universal:voucher:#{@atributos['autonomia_cartao_token']}")
    nil
  end
end
