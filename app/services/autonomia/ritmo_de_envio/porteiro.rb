# O ponto único do ritmo de envio ao cliente (#3063, item 2), antes de cada mensagem de campanha (WhatsApp Oficial, SMS,
# WhatsApp API, e-mail) e de cada mensagem que a Automação livre inicia.
#
# A consulta e a contagem são separadas (combinado com a Automação Ultra): `quando` só lê e diz se a mensagem pode sair
# agora (nil) ou a partir de que hora; `contar!` grava a mensagem que saiu de fato, depois do envio. Contar na consulta
# inflaria o limite com o que acabou não saindo (opt-out, janela fechada, texto vazio). Duas mensagens ao mesmo cliente no
# mesmo segundo podem passar juntas: o limite é de cuidado, não de cobrança.
#
# Quem não passa por aqui não conta e não espera: o aviso de renovação da carteira (decisão do Rodrigo), a resposta da
# Automação a quem acabou de escrever, o atendimento das pessoas e da IA.
#
# - Limite: no máximo `mensagens` nos últimos `dias`. Cheio, a vaga abre quando a mais velha das que contam sai do
#   período.
# - Horário: só entre `inicio` e `fim`, nos dias da semana escolhidos, no fuso do cliente (o mesmo resolvedor do CRM: o
#   fuso da ficha, o do país, o da conta). Destinatário sem ficha (e-mail de planilha) usa o fuso da conta e não conta
#   no limite.
class Autonomia::RitmoDeEnvio::Porteiro
  # A vaga do limite abre um minuto depois da saída da mensagem mais velha, para a comparação não empatar.
  FOLGA = 1.minute

  def self.quando(account:, contact:, agora: Time.current)
    new(account, contact, agora).quando
  end

  # Chamado depois que a mensagem saiu: um erro aqui não pode desfazer o envio nem fazer o motor tentar de novo (o cliente
  # receberia duas vezes). Fica no log, e a mensagem só deixa de contar.
  def self.contar!(account:, contact_id:, origem:, agora: Time.current)
    return if contact_id.blank?

    Autonomia::EnvioAoCliente.create!(account_id: account.id, contact_id: contact_id, origem: origem, enviado_em: agora)
  rescue StandardError => e
    Rails.logger.error("[ritmo_de_envio] contar falhou conta=#{account.id} contato=#{contact_id} origem=#{origem} #{e.class}")
    nil
  end

  def initialize(account, contact, agora)
    @account = account
    @contact = contact
    @agora = agora
  end

  # nil: pode mandar agora. Time: o primeiro instante em que pode.
  def quando
    config = Autonomia::RitmoDeEnvio::Config.da(@account)
    return nil if config.limite.nil? && config.horario.nil?

    livre = config.limite && @contact ? vaga_do_limite(config.limite) : @agora
    ate = config.proximo_horario(livre, fuso)
    ate > @agora ? ate : nil
  end

  private

  def vaga_do_limite(limite)
    mensagens = limite['mensagens']
    dias = limite['dias'].days
    envios = Autonomia::EnvioAoCliente.where(account_id: @account.id, contact_id: @contact.id, enviado_em: (@agora - dias)..)
                                      .order(enviado_em: :desc).limit(mensagens).pluck(:enviado_em)
    return @agora if envios.size < mensagens

    envios.last + dias + FOLGA
  end

  def fuso
    Crm::Timezone::Resolver.new(contact: @contact, account: @account).name_or_default
  end
end
