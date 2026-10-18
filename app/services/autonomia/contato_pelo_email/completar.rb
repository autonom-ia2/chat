# Contato pelo e-mail recebido (#1813): decide se vale chamar a IA e grava o que ela leu.
#
# Só lê o e-mail que saiu de um endereço do próprio contato (Crm::Email::Autoria#do_cliente?): o recebimento grava a
# mensagem em nome do contato da conversa (MailboxSanitizer), então a resposta de quem está em cópia não pode virar
# dado do dono.
#
# A gravação é a do Decisores::Aplicador, sem `trocar`: telefone só quando vazio (no formato +55..., pelo
# Decisores::Telefone, e o de outro contato vai para a biografia), e-mail só quando vazio — o e-mail do contato nunca é
# trocado. O nome, só quando é provisório (#nome_trocavel?): vazio, o e-mail, o começo do e-mail ou o telefone. O
# começo do e-mail entra de propósito: é o nome que o Chatwoot dá a todo lead do formulário do site (conta 16 da
# hub2you em 18/10: todos os leads com o nome igual ao começo do e-mail), e o formulário traz o nome de verdade.
#
# Formulário de site: o e-mail sai do endereço fixo do site, que é o contato. Só grava quando o e-mail escrito no
# formulário é um endereço do próprio contato; senão juntaria vários clientes num contato só. No e-mail de pessoa, o
# e-mail da assinatura diferente do From NÃO trava: é comum (quem escreve do gmail e assina com o da empresa, ou a
# assinatura com o "comercial@" da empresa), e travar perderia o telefone dessa gente (revisão do #1813, item 34).
#
# A IA só é chamada quando há o que completar, há texto novo, há credencial e os freios deixam (Freios). Sem
# credencial: nada acontece, sem erro. O log leva só chaves e motivos, nunca o nome, o telefone ou o e-mail.
class Autonomia::ContatoPeloEmail::Completar
  Leitor = Autonomia::ContatoPeloEmail::Leitor
  # O Aplicador grava os campos que um Decisor declara. Aqui a lista é fixa e não há Decisor salvo na conta.
  Campos = Struct.new(:id, :account, :campos, keyword_init: true)
  CAMPOS = Leitor::CAMPOS.map { |chave, destino| { 'chave' => chave, 'destino' => destino } }.freeze
  LOG = '[autonomia][contato_pelo_email]'.freeze
  # O que o Aplicador pode mudar no contato: a comparação antes/depois diz se a leitura trouxe algo novo.
  FICHA = %w[name email phone_number additional_attributes custom_attributes].freeze
  DE_NOVO_EM = 1.minute

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return unless vale_ler?

    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    return if credencial.blank?

    travado(credencial)
  rescue Leitor::Error => e
    # Sem nova tentativa: o próximo e-mail do mesmo contato tenta de novo, e repetir aqui só gastaria mais.
    Rails.logger.warn("#{LOG} message=#{@message.id} leitura falhou: #{e.message}")
  end

  private

  def contato
    @conversation.contact
  end

  # Tudo o que se confere sem gastar: a flag, o From do contato, a pausa, o que falta e o texto novo.
  def vale_ler?
    Autonomia::ContatoPeloEmail.ligado?(@account) && do_contato? && !freios.pausado?(@message.created_at) && falta_algo? &&
      Leitor.texto(@message).present?
  end

  def do_contato?
    contato.present? && contato == @message.sender && Crm::Email::Autoria.new(@account).do_cliente?(@message)
  end

  def falta_algo?
    nome_trocavel? || contato.phone_number.blank? || contato.email.blank?
  end

  def nome_trocavel?
    Autonomia::Decisores::Aplicador.nome_provisorio?(contato)
  end

  def travado(credencial)
    token = freios.travar
    return de_novo_depois if token.nil?

    begin
      ler_e_gravar(credencial)
    ensure
      freios.soltar(token)
    end
  end

  # O teto vem antes da marca "lido": o e-mail barrado pelo teto não fica marcado como lido sem ter sido.
  def ler_e_gravar(credencial)
    return motivo('teto_diario', nivel: :warn) unless freios.dentro_do_teto?
    return motivo('ja_lido') unless freios.primeira_leitura?(@message.id)

    ler_pago(credencial)
  end

  # Daqui em diante a marca "lido" está posta e a IA pode ter sido paga: a nova tentativa do job sai como `ja_lido` (não
  # paga de novo), então o erro inesperado vai ao rastreador agora, antes de subir — senão ninguém o veria. A falha da
  # própria leitura (Leitor::Error) não é bug e segue para o log de #perform.
  def ler_pago(credencial)
    leitura = Leitor.new(account: @account, credencial: credencial).ler(@message)
    return if leitura.nil?
    return automatico if leitura.tipo == Leitor::AUTOMATICO

    freios.zerar_automaticos
    return nada_novo('formulario_de_outro_endereco') if formulario_de_outro_endereco?(leitura)

    gravar(leitura)
  rescue Leitor::Error
    raise
  rescue StandardError => e
    motivo("erro_depois_da_marca erro=#{e.class.name}", nivel: :error)
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    raise
  end

  def automatico
    motivo(freios.automatico! ? 'automatico_pausa' : 'automatico')
  end

  def formulario_de_outro_endereco?(leitura)
    leitura.tipo == Leitor::FORMULARIO &&
      !Crm::Email::Autoria.new(@account).endereco_do_cliente?(@message, leitura.valores['email'])
  end

  # A IA leva segundos: a ficha é relida sob trava (with_lock relê o registro) para não gravar por cima de quem a
  # editou nesse meio-tempo. "Nada novo" é o contato igual antes e depois: o Aplicador devolve `gravado` também para o
  # valor igual ao que já estava, e isso não pode anular a pausa.
  def gravar(leitura)
    resultado, ignorados, mudou = contato.with_lock do
      antes = ficha
      fora = leitura.valores.key?('nome') && !nome_trocavel? ? ['nome'] : []
      [aplicador.aplicar(leitura.valores.except(*fora)), fora, ficha != antes]
    end
    registrar(leitura.tipo, resultado, ignorados)
    freios.pausar_por_nada_novo unless mudou
  end

  def ficha
    contato.attributes.slice(*FICHA).deep_dup
  end

  def nada_novo(razao)
    motivo(razao)
    freios.pausar_por_nada_novo
  end

  def aplicador
    Autonomia::Decisores::Aplicador.new(decisor: Campos.new(id: 'contato_pelo_email', account: @account, campos: CAMPOS),
                                        conversation: @conversation)
  end

  def freios
    @freios ||= Autonomia::ContatoPeloEmail::Freios.new(account_id: @account.id, contato_id: contato.id)
  end

  # Outro e-mail do mesmo contato está sendo lido: este volta para a fila depois, em vez de se perder (o segundo e-mail
  # pode ser o que traz o telefone). A trava expira sozinha (Freios::TRAVA_POR), então a volta sempre termina.
  def de_novo_depois
    Autonomia::ContatoPeloEmailJob.set(wait: DE_NOVO_EM).perform_later(@message.id)
    motivo('em_andamento')
  end

  def motivo(razao, nivel: :info)
    Rails.logger.public_send(nivel, "#{LOG} message=#{@message.id} contato=#{contato.id} motivo=#{razao}")
  end

  # Só as chaves e os motivos: o valor (nome, telefone, e-mail) não vai para o log.
  def registrar(tipo, resultado, ignorados)
    Rails.logger.info("#{LOG} message=#{@message.id} contato=#{contato.id} tipo=#{tipo} " \
                      "gravados=#{resultado.aplicados.keys.join(',')} " \
                      "recusados=#{(resultado.recusados.keys + ignorados).join(',')}")
  end
end
