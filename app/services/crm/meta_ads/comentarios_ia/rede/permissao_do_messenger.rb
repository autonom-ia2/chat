# IA cuida dos comentários (#2307): a Página pode mandar o privado pelo Messenger? Responde o que a Meta concedeu ao
# login da caixa, não uma flag nossa. O privado (Private Replies) pede a `pages_messaging` no token da Página, e o token
# da Página tem as permissões do login de quem ligou a caixa (o `user_access_token` dela): GET /me/permissions com ele.
#
# - Concedida: libera. Quem tem papel no app (administrador, desenvolvedor, testador) recebe a permissão sem a análise da
#   Meta (acesso padrão); os clientes, no dia em que a Meta aprovar e eles entrarem de novo. Sem deploy.
# - Recusada, vencida ou fora da lista: não libera. A tela diz que a Meta ainda não liberou; a pergunta fica com o dono.
# - Sem resposta da lista (Meta fora do ar, login de mais de 60 dias): não dá para saber. Libera, e quem decide é a
#   própria chamada do privado: a Meta recusando por permissão (`recusou!`), a Página fica sem o privado por RECUSA_TTL,
#   e cada comentário seguinte fica com o dono, sem bater de novo na Meta.
#
# A resposta fica guardada pela caixa e pela última mudança dela (`updated_at`): entrar de novo troca os tokens e lê de
# novo na hora.
class Crm::MetaAds::ComentariosIa::Rede::PermissaoDoMessenger
  PERMISSAO = 'pages_messaging'.freeze
  CONCEDIDA = 'granted'.freeze
  SIM = 'sim'.freeze
  NAO = 'nao'.freeze
  SEM_RESPOSTA = 'sem_resposta'.freeze
  LIDA_TTL = 1.hour
  SEM_RESPOSTA_TTL = 5.minutes
  RECUSA_TTL = 6.hours

  def initialize(channel)
    @channel = channel
  end

  def liberada?
    return false unless @channel.is_a?(Channel::FacebookPage)
    return false if Rails.cache.read(chave('recusou'))

    lida != NAO
  end

  # A Meta recusou o privado por permissão (código 10 ou 200–299): a Página fica sem o privado por RECUSA_TTL.
  def recusou!
    Rails.cache.write(chave('recusou'), true, expires_in: RECUSA_TTL)
  end

  private

  def lida
    guardada = Rails.cache.read(chave('lida'))
    return guardada if guardada

    resposta = ler
    Rails.cache.write(chave('lida'), resposta, expires_in: resposta == SEM_RESPOSTA ? SEM_RESPOSTA_TTL : LIDA_TTL)
    resposta
  end

  def ler
    return SEM_RESPOSTA if @channel.user_access_token.blank?

    result = Meta::AdsGraphClient.new(access_token: @channel.user_access_token).permissions
    return SEM_RESPOSTA unless result.ok

    concedida?(result.data) ? SIM : NAO
  end

  def concedida?(data)
    Array(data.to_h['data']).any? { |row| row.is_a?(Hash) && row['permission'] == PERMISSAO && row['status'] == CONCEDIDA }
  end

  def chave(o_que)
    "comentarios_ia:pages_messaging:#{o_que}:#{@channel.id}:#{@channel.updated_at.to_i}"
  end
end
