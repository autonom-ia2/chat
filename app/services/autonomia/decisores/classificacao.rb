# O Jev classificando uma lista de itens numa pergunta de múltipla escolha, para o Guia (#858,
# ferramenta `classificar_com_jev`): "desses contatos, quais vieram do formulário do site?".
#
# É o mesmo Jev do Decisor, com a pergunta montada na hora e sem nada guardado — nem decisão, nem
# exemplo. O custo é NOSSO e fica em `Crm::AiUsageEvent` com a feature `jev_guia`.
#
# Os itens vão em sequência, com prazo total de 60 s: o Guia roda em job, mas um turno não pode ficar
# preso. Estourou o prazo, devolve o que deu e diz quantos ficaram de fora. Nenhuma chamada repete
# aqui dentro: uma nova tentativa gastaria o prazo dos itens seguintes.
class Autonomia::Decisores::Classificacao
  FEATURE = 'jev_guia'.freeze
  PRAZO = 60.0
  JEV_LEITURA = 5
  # Abaixo disto não começa uma chamada nova: ela não terminaria antes do prazo.
  FOLGA = TypesafeAi::Client::OPEN_TIMEOUT + JEV_LEITURA

  def self.cota_esgotada?(account)
    Crm::AiUsageEvent.where(account_id: account.id, feature: FEATURE, created_at: Time.current.all_month)
                     .count >= Autonomia::Decisores::LIMITE_MENSAL
  end

  # `pergunta` é um Decisor não salvo: só a pergunta e as opções, para o Jev ler do mesmo jeito.
  def initialize(pergunta:, relogio: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @pergunta = pergunta
    @relogio = relogio
    @comeco = relogio.call
  end

  # `casos`: [{ ref:, estado: }] ou [{ ref:, erro: }] (o item que nem chegou a ser lido).
  def perform(casos)
    itens = casos.map { |caso| caso[:erro] ? caso.slice(:ref, :erro) : classificar(caso) }
    { itens: itens, resumo: resumo(itens), classificados: itens.count { |item| item[:escolha] },
      fora_do_prazo: itens.count { |item| item[:erro] == 'fora_do_prazo' } }
  end

  private

  def classificar(caso)
    return { ref: caso[:ref], erro: 'fora_do_prazo' } if restante < FOLGA

    resultado = jev.decidir(decisor: @pergunta, estado: caso[:estado])
    { ref: caso[:ref], escolha: resultado.resposta, certeza: resultado.certeza.round(2) }
  rescue TypesafeAi::Decisor::Error => e
    { ref: caso[:ref], erro: e.code }
  end

  def resumo(itens)
    contagem = @pergunta.chaves.index_with { 0 }.merge(itens.filter_map { |item| item[:escolha] }.tally)
    contagem.merge('sem_resposta' => itens.count { |item| item[:escolha].nil? })
  end

  def restante
    PRAZO - (@relogio.call - @comeco)
  end

  def jev
    @jev ||= TypesafeAi::Decisor.new(client: TypesafeAi::Client.new(read_timeout: JEV_LEITURA, retry_limit: 0), feature: FEATURE)
  end
end
