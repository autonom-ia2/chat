# O que os quatro passos de IA da F7 (#2500) têm em comum. Agem na conversa do alvo, como "mensagem" e "avisar"
# (NaConversa): quem ligou precisa enxergá-la, e no card vale a conversa principal.
#
# A IA lê só o que o passo declara em `le`, pelo Estado do Decisor (lista fechada; o e-mail e o telefone do contato
# nunca vão). O resultado de cada passo é entregue ali mesmo, como nota, mensagem ou gravação: nada do que a IA escreveu
# fica guardado entre passos, e o registro leva só ids, chaves e o custo, nunca texto da conversa.
module Autonomia::Automacao::ComIa
  include ::Autonomia::Automacao::NaConversa

  Falha = ::Autonomia::Automacao::PassoDeIa::Falha

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

  def leitura
    leituras = Array(@passo['le']).presence || ::Autonomia::Decisor::LEITURAS_PADRAO
    ::Autonomia::Decisores::Estado.new(conversation: @conversa, leituras: leituras)
  end

  # [resposta, custo]; a Falha vira o Resultado do tipo que o executor entende.
  def perguntar(modelo:, instrucoes:, entrada:, schema:)
    ia = ::Autonomia::Automacao::PassoDeIa.new(conta: @conversa.account, feature: "automacao_#{@passo['tipo']}", modelo: modelo)
    ia.perguntar(instrucoes: instrucoes, entrada: entrada, schema: schema)
  end

  def falhou(falha) = Resultado.new(tipo: falha.tipo, motivo: falha.motivo, dados: {})

  def nota(texto) = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: [], marca: marca)

  # O texto fixo da nota, no idioma da conta (como a nota do AntiLaco).
  def frase(chave, **valores)
    I18n.with_locale(@conversa.account.locale) { I18n.t("autonomia.automacao.nota.#{chave}", **valores) }
  end
end
