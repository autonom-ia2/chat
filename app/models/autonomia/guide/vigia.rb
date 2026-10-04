# Uma leitura da conta que o Guia mede sozinho, com um gatilho numérico (#935).
#
# O Guia só falava quando chamado: uma automação disparando 40 vezes ou uma conexão caída só
# apareciam quando já tinham virado prejuízo. A vigia é o "me avisa se…": a mesma leitura que o Guia
# faz com `ler_da_conta`, um número tirado dela (`medida`) e o limite que vale um aviso (`gatilho`).
# Cenário novo é dado (uma vigia nova), nunca código.
#
# A leitura sai com a permissão de quem criou a vigia, sempre um administrador. Quem deixa de ser
# administrador tem as vigias pausadas no pulso seguinte (`Pulso`).
#
# O formato de `leitura`, `gatilho` e `para_quem` mora nos esquemas abaixo: o Guia lê esses esquemas
# no `formato_da_acao` de `POST autonomia/vigias` e confere o corpo antes de gravar.
class Autonomia::Guide::Vigia < ApplicationRecord
  self.table_name = 'autonomia_guide_vigias'

  TETO_POR_CONTA = 20
  ORIGENS = %w[pessoa padrao].freeze
  GRAVIDADES = %w[info agir urgente].freeze
  MEDIDAS = %w[contagem soma maior valor].freeze
  # A média só vale depois de alguns dias: antes disso, "3× a média" dispararia por qualquer coisa.
  HISTORICO_MINIMO = 3.days
  # A média acompanha a última semana de medições (a cada 15 min).
  AMOSTRAS_NA_MEDIA = 7 * 24 * 4
  JANELA_PADRAO_HORAS = 24

  ESCALAR = { 'type' => %w[string integer number boolean null] }.freeze

  LEITURA = {
    'type' => 'object', 'additionalProperties' => false, 'required' => %w[rota medida],
    'properties' => {
      'rota' => { 'type' => 'string', 'minLength' => 1,
                  'description' => 'A leitura da conta, igual à de ler_da_conta (ex.: "inboxes", "automation_rules").' },
      'parametros' => { 'type' => 'object', 'additionalProperties' => { 'type' => %w[string integer] },
                        'description' => 'Os parâmetros da leitura, como em ler_da_conta (o id do caminho e os filtros).' },
      'medida' => {
        'type' => 'object', 'additionalProperties' => false, 'required' => %w[tipo],
        'description' => 'O número tirado da leitura.',
        'properties' => {
          'tipo' => { 'enum' => MEDIDAS,
                      'description' => 'contagem: quantos itens; soma e maior: de um campo numérico dos itens; ' \
                                       'valor: um número da resposta.' },
          'campo' => { 'type' => 'string', 'minLength' => 1,
                       'description' => 'O campo numérico, com ponto para descer (ex.: "disparos.ultimas_24h"). ' \
                                        'Obrigatório em soma, maior e valor.' },
          'onde' => { 'type' => 'object', 'additionalProperties' => ESCALAR,
                      'description' => 'Só os itens com estes valores (ex.: {"reauthorization_required": true}).' }
        },
        'if' => { 'properties' => { 'tipo' => { 'enum' => %w[soma maior valor] } } },
        'then' => { 'required' => %w[campo] }
      }
    }
  }.freeze

  GATILHO = {
    'type' => 'object', 'additionalProperties' => false,
    'description' => 'Avisa quando TODAS as condições dadas valem. Dê pelo menos uma.',
    'anyOf' => [{ 'required' => %w[acima_de] }, { 'required' => %w[abaixo_de] }, { 'required' => %w[vezes_a_media] }],
    'properties' => {
      'acima_de' => { 'type' => 'number', 'description' => 'Avisa quando a medida passa deste número.' },
      'abaixo_de' => { 'type' => 'number', 'description' => 'Avisa quando a medida fica abaixo deste número.' },
      'vezes_a_media' => { 'type' => 'number', 'minimum' => 1.5,
                           'description' => 'Avisa quando a medida passa N vezes a média da última semana. ' \
                                            'Só vale com 3 dias de medições.' },
      'janela_horas' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 168,
                          'description' => 'Avisa no máximo uma vez a cada tantas horas. Padrão: 24.' }
    }
  }.freeze

  PARA_QUEM = {
    'type' => 'array', 'maxItems' => 50, 'items' => { 'type' => 'integer' },
    'description' => 'Os administradores que recebem o aviso (ids). Vazio: todos os administradores.'
  }.freeze

  belongs_to :account
  belongs_to :criado_por, class_name: 'User', optional: true

  validates :nome, presence: true, length: { maximum: 120 }
  validates :origem, inclusion: { in: ORIGENS }
  validates :gravidade, inclusion: { in: GRAVIDADES }
  validates :leitura, json_schema: { schema: LEITURA }
  validates :gatilho, json_schema: { schema: GATILHO }
  validates :para_quem, json_schema: { schema: PARA_QUEM }
  validate :rota_da_conta
  validate :cabe_no_teto, on: :create

  scope :da_conta, ->(account) { where(account: account) }
  scope :medindo, -> { where(ativa: true).where('silenciada_ate IS NULL OR silenciada_ate <= ?', Time.current) }

  def medida = leitura.fetch('medida', {})
  def janela_horas = gatilho.fetch('janela_horas', JANELA_PADRAO_HORAS)

  # A janela em que um momento cai: a mesma vigia avisa no máximo uma vez por janela.
  def janela(momento = Time.current)
    (momento.to_i / janela_horas.hours.to_i).to_s
  end

  def media = linha_de_base['media']&.to_f

  def historico_suficiente?(agora = Time.current)
    desde = linha_de_base['desde']
    desde.present? && Time.zone.parse(desde) <= agora - HISTORICO_MINIMO
  end

  # O valor cruza o gatilho? Todas as condições dadas têm de valer. A média é a de antes desta medição.
  def cruzou?(valor, agora = Time.current)
    condicoes = []
    condicoes << (valor > gatilho['acima_de']) if gatilho.key?('acima_de')
    condicoes << (valor < gatilho['abaixo_de']) if gatilho.key?('abaixo_de')
    if gatilho.key?('vezes_a_media')
      return false unless historico_suficiente?(agora)

      condicoes << (valor > media.to_f * gatilho['vezes_a_media'])
    end
    condicoes.any? && condicoes.all?
  end

  # Soma a medição à média da última semana.
  def medir!(valor, agora = Time.current)
    amostras = [linha_de_base['amostras'].to_i, AMOSTRAS_NA_MEDIA - 1].min
    nova_media = ((media.to_f * amostras) + valor) / (amostras + 1)
    update!(linha_de_base: { 'desde' => linha_de_base['desde'] || agora.iso8601, 'amostras' => amostras + 1,
                             'media' => nova_media.round(4) })
  end

  def para_tela
    { 'id' => id, 'nome' => nome, 'origem' => origem, 'leitura' => leitura, 'gatilho' => gatilho, 'para_quem' => para_quem,
      'gravidade' => gravidade, 'ativa' => ativa, 'silenciada_ate' => silenciada_ate&.iso8601, 'criado_por_id' => criado_por_id,
      'media' => media, 'medindo_desde' => linha_de_base['desde'], 'criada_em' => created_at&.iso8601 }
  end

  private

  # A leitura tem de ser uma das que o Guia faz na conta (`ler_da_conta`).
  def rota_da_conta
    rota = leitura.is_a?(Hash) ? leitura['rota'].to_s.strip.delete_prefix('/') : ''
    return if rota.blank? || ::Autonomia::Guide::Consulta.new(account: account, user: nil).catalogo.include?(rota)

    errors.add(:leitura, "rota #{rota.to_json} não é uma leitura da conta")
  end

  def cabe_no_teto
    return if account.nil? || self.class.da_conta(account).count < TETO_POR_CONTA

    errors.add(:base, "a conta já tem #{TETO_POR_CONTA} vigias; apague ou ajuste uma")
  end
end
