# "Apólice nova" feita à mão, a partir do seguro que renovou (E5, #2898): a pessoa digita a apólice que chegou da
# seguradora e diz qual ela renovou. Nasce um seguro novo, da mesma pessoa e da mesma empresa da anterior, com a origem
# `manual`, já ligado à anterior; a anterior fica renovada (Carteira::Renovacao::Ligar). Quem grava é o gravador único
# da carteira (Carteira::Guardar); a história da nova começa com "Apólice nova guardada. A anterior era a ...".
#
# Seguradora, tipo e fim da vigência são obrigatórios; número, começo, valor e item, não (o que vier vazio fica sem).
#
# Recusas (CustomExceptions::CarteiraRecusa), além das de leitura de cada campo (Carteira::LeituraDoPedido):
# - `anterior_cancelada`, `ja_tem_desfecho` (a anterior está como "não renovou": desfaça antes) e
#   `ja_tem_apolice_nova` (outra apólice já renovou a anterior);
# - `falta_tipo`, `falta_seguradora`, `falta_termina`, `termina_antes` (o fim antes do começo) e
#   `termina_antes_da_anterior` (a apólice nova tem de terminar depois da que ela renova);
# - as do gravador, que sobem como vieram e não mudam nada: `apolice_repetida` (a conta já tem essa apólice: a mesma
#   seguradora e o mesmo número, com o mesmo começo ou o mesmo fim da vigência; quem a corrige é a gaveta dela),
#   `apolice_de_outra_pessoa` (essa seguradora e esse número já estão guardados para outro contato) e `termo_ambiguo`
#   (há mais de uma vigência guardada dessa apólice que pode ser a digitada).
#
# A renovação que mantém a seguradora e o número é outro termo da mesma apólice (Carteira::Termo): nasce a linha nova, e é
# ela que se liga à anterior.
class Carteira::Renovacao::ApoliceNova
  CAMPOS = (%w[anteriorId] + Carteira::Campos::COLUNAS.keys).freeze
  OBRIGATORIOS = %w[tipo seguradora termina].freeze
  ORIGEM = 'manual'.freeze

  def initialize(anterior, dados, user:)
    @anterior = anterior
    @dados = dados.to_h.stringify_keys.slice(*Carteira::Campos::COLUNAS.keys)
    @user = user
  end

  def call
    conferir_anterior
    dados = ler
    Carteira::Apolice.transaction(requires_new: true) do
      nova = gravador.call(dados, contato: @anterior.contact, empresa: @anterior.company).apolice
      Carteira::Renovacao::Ligar.new(nova, user: @user).com(@anterior, anotar: false)
    end
  end

  private

  def conferir_anterior
    recusar('anterior_cancelada') if @anterior.cancelado_em
    recusar('ja_tem_desfecho') if @anterior.nao_renovou_em
    recusar('ja_tem_apolice_nova') if Carteira::Apolice.exists?(account_id: @anterior.account_id, apolice_anterior_id: @anterior.id)
  end

  def ler
    falta = OBRIGATORIOS.find { |campo| @dados[campo].blank? }
    recusar("falta_#{falta}") if falta

    dados = Carteira::LeituraDoPedido.new(@dados.compact_blank).atributos
    recusar('termina_antes') if dados[:inicio_vigencia] && dados[:fim_vigencia] < dados[:inicio_vigencia]
    recusar('termina_antes_da_anterior') unless dados[:fim_vigencia] > @anterior.fim_vigencia
    dados
  end

  def gravador
    Carteira::Guardar.new(@anterior.account, origem: ORIGEM, user: @user, chegada: Carteira::Renovacao::Ligar::PASSO,
                                             valores: { anterior: @anterior.numero })
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
