# Uma revisão de conversas em lote do Guia (#3158, B8b): "revise as conversas com nota 1 e 2 desta semana e diga
# os motivos".
#
# A ferramenta `revisar_conversas` escolhe as conversas (`Revisoes::Selecao`) e cria a revisão; o `RevisaoJob` lê
# uma por uma, com a IA da conta (`Revisoes::Revisor`), e guarda o motivo de cada uma. O cartão do Guia acompanha
# por `GET guide/revisoes/:id` e, no fim, mostra os motivos agrupados.
#
# Só lê: nada da conta muda. Por isso não tem amostra, pausa de segurança nem desfazer, como a `Tarefa`. Para parar,
# a pessoa escreve no Guia e a IA chama `revisar_conversas` com `acao: parar` (#3143): sem botão Parar.
class Autonomia::Guide::Revisao < ApplicationRecord
  self.table_name = 'autonomia_guide_reviews'

  # Por vez, como o Copilot (`copilot_run.rb`); "ler as que faltam" soma mais 300.
  POR_VEZ = 300
  # As conversas que entram na escolha. Acima disso, o Guia pede para estreitar o filtro.
  MAX_IDS = 5_000
  # Categorias mostradas; o resto vira "Outros motivos".
  CATEGORIAS = 5

  NA_FILA = 'na_fila'.freeze
  RODANDO = 'rodando'.freeze
  CONCLUIDA = 'concluida'.freeze
  PARADA = 'parada'.freeze
  FALHOU = 'falhou'.freeze
  STATUS = [NA_FILA, RODANDO, CONCLUIDA, PARADA, FALHOU].freeze
  ANDANDO = [NA_FILA, RODANDO].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :turno, class_name: 'Autonomia::Guide::Turno', optional: true

  validates :status, inclusion: { in: STATUS }
  validates :titulo, :pedido, presence: true

  scope :de, ->(account, user) { where(account: account, user: user) }
  scope :andando, -> { where(status: ANDANDO) }

  def andando?
    ANDANDO.include?(status)
  end

  def total
    ids.size
  end

  # Até onde ler agora: o limite, sem passar do total.
  def ate
    [limite, total].min
  end

  def proximo_id
    posicao < ate ? ids[posicao] : nil
  end

  # Muda de estado só se ainda estiver num dos estados de origem. Em SQL, de uma vez: o job e a pessoa (parar,
  # ler as que faltam) podem chegar juntos.
  def mudar!(origens, destino, **extra)
    mudou = self.class.where(id: id, status: Array(origens))
                .update_all(extra.merge(status: destino, updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    reload
    mudou == 1
  end

  def parar!
    mudar!(ANDANDO, PARADA)
  end

  # "Ler as que faltam": mais 300, a partir de onde parou. Só depois do fim da vez anterior.
  def continuar!
    return false if posicao >= total

    mudar!([CONCLUIDA, PARADA], NA_FILA, limite: posicao + POR_VEZ, motivo: nil, batimento_em: Time.current)
  end

  # O que a ferramenta devolve ao modelo e o aviso da revisão em andamento: só números.
  def resumo
    "#{lidas} de #{ate} lidas (#{total} escolhidas)#{" e #{falhas} não abriram" if falhas.positive?}"
  end

  def para_tela
    { 'id' => id, 'status' => status, 'titulo' => titulo, 'de' => selecao['de'], 'ate' => selecao['ate'],
      'total' => total, 'limite' => ate, 'lidas' => lidas, 'falhas' => falhas, 'faltam' => total - posicao,
      'motivo' => motivo, 'categorias' => andando? ? [] : categorias }
  end

  # Os motivos agrupados, do mais comum ao menos; acima de `CATEGORIAS`, o resto junto em "outros" (o rótulo é
  # da tela). Cada categoria leva as conversas dela, para a pessoa abrir.
  def categorias
    grupos = resultados.group_by { |resultado| resultado['categoria'] }
                       .map { |nome, itens| { 'nome' => nome, 'conversas' => itens.map { |item| item.slice('numero', 'motivo') } } }
                       .sort_by { |grupo| [-grupo['conversas'].size, grupo['nome'].to_s] }
    return grupos if grupos.size <= CATEGORIAS + 1

    grupos.first(CATEGORIAS) + [{ 'nome' => nil, 'outros' => true, 'conversas' => grupos.drop(CATEGORIAS).flat_map { |grupo| grupo['conversas'] } }]
  end

  # As categorias que a IA já deu nesta revisão, da mais comum, para ela repetir o mesmo nome e a contagem valer.
  def categorias_conhecidas(limite = 20)
    resultados.pluck('categoria').tally.sort_by { |nome, quantas| [-quantas, nome] }.first(limite).map(&:first)
  end
end
