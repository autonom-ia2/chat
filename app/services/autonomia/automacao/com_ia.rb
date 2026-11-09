# O que os quatro passos de IA da F7 (#2500) têm em comum. Agem na conversa do alvo, como "mensagem" e "avisar"
# (NaConversa): quem ligou precisa enxergá-la, e no card vale a conversa principal.
#
# A IA lê só o que o passo declara em `le`, pelo Estado do Decisor (lista fechada; o e-mail e o telefone do contato
# nunca vão). O resultado de cada passo é entregue ali mesmo, como nota, mensagem ou gravação. O texto do "escrever" e do
# "resumir" fica também na execução (#2679), para um passo seguinte ler como `ia.<passo>`, e some quando ela termina. O
# registro leva só ids, chaves e o custo, nunca texto da conversa.
module Autonomia::Automacao::ComIa
  include ::Autonomia::Automacao::NaConversa

  Falha = ::Autonomia::Automacao::PassoDeIa::Falha

  # O que o passo lê: o `le` dele, ou o padrão do Decisor. O "Testar este passo" (#2500 C2) lê o mesmo.
  # Os anexos (G20) não são do Estado: o passo que lê só os anexos lê também as mensagens recentes, como o padrão.
  def self.leituras(passo)
    ::Autonomia::Automacao::AnexosDaConversa.sem_anexos(passo['le']).presence || ::Autonomia::Decisor::LEITURAS_PADRAO
  end

  VALOR = 'card.valor'.freeze
  DECIDE = 'decidir'.freeze

  # O valor do card vai à IA? Só com a chave de quem lê (#2597, Valores.pode_ler?) e, na automação de conversa, só no
  # passo que decide (#2780, Valores.so_decide?): o que escreve (escrever, resumir, extrair) não o leva ao texto. A
  # automação de card segue só com a chave. `gatilho`: o tipo do gatilho da receita, como no salvar.
  def self.leva_o_valor?(passo, gatilho, account_user)
    valores = ::Autonomia::Automacao::Valores
    valores.pode_ler?(VALOR, account_user) && (passo['tipo'] == DECIDE || !valores.so_decide?(VALOR, gatilho))
  end

  # `usuario` vê o card? A pergunta do resto do CRM (Crm::CardPolicy#show?). Quem saiu da conta não vê.
  def self.ve_o_card?(usuario, card)
    account_user = usuario && card.account.account_users.find_by(user_id: usuario.id)
    return false unless account_user

    ::Crm::CardPolicy.new({ user: usuario, account: card.account, account_user: account_user }, card).show?
  end

  def initialize(execucao:, passo:, alvo:, acesso:)
    super(execucao: execucao, passo: passo, alvo: alvo)
    @acesso = acesso
  end

  # nil quando o passo pode seguir para a IA; senão o Resultado (sem conversa, quem ligou não a vê).
  def impedido
    return sem_conversa if @conversa.nil?

    sem_acesso
  end

  private

  # Com `fuso`, cada mensagem vai com a data e a hora dela (o extrair precisa para "ontem"). Com `le: anexos` (G20), os
  # anexos da conversa vão junto (AnexosDaConversa).
  def leitura(fuso: nil)
    leituras = ::Autonomia::Automacao::ComIa.leituras(@passo)
    estado = estado_com(leituras, fuso)
    estado = estado_com(leituras - ['card'], fuso) unless card_visivel?(leituras, estado)
    @leitura = ::Autonomia::Automacao::AnexosDaConversa.leitura(estado, @passo, @conversa)
  end

  # `le: card` (#2679): no gatilho de card, o próprio card; no de conversa, o card dela (o Estado acha).
  def estado_com(leituras, fuso)
    ::Autonomia::Decisores::Estado.new(conversation: @conversa, card: (@alvo if @alvo.is_a?(::Crm::Card)), leituras: leituras, fuso: fuso,
                                       valor_do_card: ve_o_valor_do_card?, motivo_da_perda: true)
  end

  # O card vai à IA só se quem ligou a automação o vê (a pergunta do resto do CRM); senão o passo lê o resto.
  def card_visivel?(leituras, estado)
    leituras.exclude?('card') || estado.card.nil? || ::Autonomia::Automacao::ComIa.ve_o_card?(@execucao.automacao.ligada_por, estado.card)
  end

  # #2597: a leitura "card" leva o valor só se quem ligou a automação pode lê-lo, a mesma regra do Valores; #2780: na
  # automação de conversa, só no "decidir" (ComIa.leva_o_valor?). Quem saiu da conta não lê. O anúncio de origem (#2558)
  # nunca vai: todo passo de IA escreve texto livre (nota, mensagem, resumo).
  def ve_o_valor_do_card?
    quem = @execucao.automacao.ligada_por
    na_conta = quem && @conversa.account.account_users.find_by(user_id: quem.id)
    gatilho = ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao).gatilho
    ::Autonomia::Automacao::ComIa.leva_o_valor?(@passo, gatilho, na_conta)
  end

  # O fuso que a tela grava na conta (#954, o mesmo do Guia); sem ele, o padrão da plataforma (Crm::Timezone::Resolver).
  def fuso_da_conta
    conta = @conversa.account
    ::Crm::Timezone::Resolver.new(explicit: conta.custom_attributes.to_h['timezone'], account: conta).zone_or_default
  end

  # [resposta, custo]; a Falha vira o Resultado do tipo que o executor entende. O anexo que não pode ir à IA (G20) faz o
  # passo pular, sem chamá-la.
  def perguntar(modelo:, instrucoes:, entrada:, schema:)
    ia = ::Autonomia::Automacao::PassoDeIa.new(conta: @conversa.account, feature: "automacao_#{@passo['tipo']}", modelo: modelo)
    ia.perguntar(instrucoes: instrucoes, entrada: entrada, schema: schema, anexos: @leitura&.anexos&.partes(modelo: modelo) || [])
  rescue ::Autonomia::Automacao::AnexosDaConversa::Recusa => e
    raise Falha.new(:pulado, e.motivo)
  end

  def falhou(falha) = Resultado.new(tipo: falha.tipo, motivo: falha.motivo, dados: {})

  # #2679: o texto fica na execução, para os passos seguintes (Valores, `ia.<passo>`).
  def guardar(texto) = @execucao.guardar_texto!(@passo['id'], texto)

  # Nada para a IA ler (sem mensagem do cliente, contato sem nada): o passo pula sem pagar uma resposta vazia. Proteção
  # contra defeito, não freio de uso.
  def nada_para_ler = Resultado.new(tipo: :pulado, motivo: 'nada_para_ler', dados: {})

  def nota(texto) = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: [], marca: marca)

  # O texto fixo da nota, no idioma da conta (como a nota do AntiLaco).
  def frase(chave, **valores)
    I18n.with_locale(@conversa.account.locale) { I18n.t("autonomia.automacao.nota.#{chave}", **valores) }
  end
end
