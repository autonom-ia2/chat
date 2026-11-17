# As escolhas da cotação da renovação que "Ajustar renovações" grava (E8, #2901), conferidas antes de entrar na linha de
# ajustes da conta (Carteira::Renovacao::SalvarAjustes). Só muda o que veio:
# - `quemCota`: `robo`, `lia` ou `ninguem`. `robo` e `lia` só na conta que tem o Agente de Cotação, porque é com ele que
#   a cotação roda (recusa `sem_agente_de_cotacao`);
# - `quemEnvia`: `pessoa` (alguém confere e aperta Enviar no card) ou `sozinho`;
# - `quemResponde`: `lia` ou `equipe`;
# - `caixaId`: a caixa do WhatsApp oficial da conta por onde as mensagens saem, ou nulo para tirar (recusa
#   `caixa_invalida` para a caixa de outra conta ou que não é do WhatsApp oficial).
#
# Com o robô cotando, a Lia respondendo e uma caixa que entrega toda conversa nova a alguém da equipe
# (Carteira::Cotacao.caixa_distribui?), a Lia nunca responderia: `caixa_distribui`. Vale o que fica gravado, juntando o que
# veio com o que a conta já tinha.
#
# Valor fora da lista é `escolha_invalida`. Sem a chave da cotação na conta, nenhuma destas escolhas é aceita
# (`cotacao_desligada`): a tela nem as mostra, e a renovação fica a da E5. A recusa nunca repete o que foi mandado.
class Carteira::Cotacao::Escolhas
  CAMPOS = %w[quemCota quemEnvia quemResponde caixaId].freeze
  Config = Carteira::RenovacaoConfig

  def initialize(account, dados)
    @account = account
    @dados = dados.to_h.stringify_keys.slice(*CAMPOS)
  end

  # -> os atributos da linha de ajustes que mudam ({} quando nenhuma escolha da cotação veio).
  def call
    return {} if @dados.empty?

    recusar('cotacao_desligada') unless Carteira::Cotacao::Liberada.para?(@account)
    novos = quem_cota.merge(escolha('quemEnvia', :quem_envia, Config::QUEM_ENVIA))
                     .merge(escolha('quemResponde', :quem_responde, Config::QUEM_RESPONDE))
                     .merge(caixa)
    recusar('caixa_distribui') if lia_numa_caixa_que_distribui?(novos)
    novos
  end

  private

  def lia_numa_caixa_que_distribui?(novos)
    config = Config.find_by(account_id: @account.id)
    quem_cota = novos.fetch(:quem_cota) { config&.quem_cota }
    quem_responde = novos.fetch(:quem_responde) { config&.quem_responde }
    inbox = novos.key?(:inbox) ? novos[:inbox] : config&.inbox
    [Config::ROBO, Config::LIA].include?(quem_cota) && quem_responde == Config::LIA && Carteira::Cotacao.caixa_distribui?(inbox)
  end

  def quem_cota
    valor = escolha('quemCota', :quem_cota, Config::QUEM_COTA)
    com_robo = [Config::ROBO, Config::LIA].include?(valor[:quem_cota])
    recusar('sem_agente_de_cotacao') if com_robo && Carteira::Cotacao.agente(@account).nil?
    valor
  end

  def escolha(campo, coluna, lista)
    return {} unless @dados.key?(campo)

    recusar('escolha_invalida') unless lista.include?(@dados[campo])
    { coluna => @dados[campo] }
  end

  def caixa
    return {} unless @dados.key?('caixaId')
    return { inbox: nil } if @dados['caixaId'].nil?

    inbox = @account.inboxes.find_by(id: inteiro(@dados['caixaId']))
    recusar('caixa_invalida') unless inbox && Whatsapp::Templates::MetaClient.supported?(inbox)
    { inbox: inbox }
  end

  # O número inteiro que veio, como número ou como texto só de dígitos. O resto é nulo.
  def inteiro(valor)
    valor.is_a?(Integer) ? valor : Integer(valor.to_s, 10, exception: false)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
