# IA cuida dos comentários (#2307): a Página pode mandar o privado pelo Messenger? Responde o que a Meta concedeu ao
# login da caixa, não uma flag nossa. O privado (Private Replies) pede a `pages_messaging` no token da Página, e o token
# da Página tem as permissões do login de quem ligou a caixa (o `user_access_token` dela): GET /me/permissions com ele.
#
# - Concedida: libera. Quem tem papel no app (administrador, desenvolvedor, testador) recebe a permissão sem a análise da
#   Meta (acesso padrão); os clientes, no dia em que a Meta aprovar e eles entrarem de novo. Sem deploy.
# - Recusada, vencida ou fora da lista: não libera. A tela diz que a Meta ainda não liberou; a pergunta fica com o dono.
# - Sem resposta da lista (Meta fora do ar ou lenta, login de mais de 60 dias, cujo token de Página continua valendo):
#   não dá para saber. Libera, e quem decide é a própria chamada do privado: a recusa da Meta por permissão deixa
#   aquele comentário com o dono, dizendo isso (Painel, `no_permission`). A recusa não tira o privado da Página
#   inteira: no acesso padrão ela pode ser só daquela pessoa (quem comentou sem papel no app).
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
  # A leitura roda dentro da tela do cuidado: a Meta lenta não a segura mais do que isso.
  PRAZO_SEGUNDOS = 3

  def initialize(channel)
    @channel = channel
  end

  def liberada?
    return false unless @channel.is_a?(Channel::FacebookPage)

    lida != NAO
  end

  private

  def lida
    guardada = Rails.cache.read(chave)
    return guardada if guardada

    resposta = ler
    Rails.cache.write(chave, resposta, expires_in: resposta == SEM_RESPOSTA ? SEM_RESPOSTA_TTL : LIDA_TTL)
    resposta
  end

  def ler
    return SEM_RESPOSTA if @channel.user_access_token.blank?

    prazo = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PRAZO_SEGUNDOS
    result = Meta::AdsGraphClient.new(access_token: @channel.user_access_token, prazo: prazo).permissions
    return SEM_RESPOSTA unless result.ok

    concedida?(result.data) ? SIM : NAO
  end

  def concedida?(data)
    Array(data.to_h['data']).any? { |row| row.is_a?(Hash) && row['permission'] == PERMISSAO && row['status'] == CONCEDIDA }
  end

  def chave
    "comentarios_ia:pages_messaging:#{@channel.id}:#{@channel.updated_at.to_i}"
  end
end
