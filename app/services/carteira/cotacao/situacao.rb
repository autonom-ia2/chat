# Onde a cotação da renovação de cada seguro está (E8, #2901), no formato que a tela lê (Carteira::Apresentacao, chave
# `cotacao`). Só os passos da vigência que vale agora; sem passo nenhum, nulo.
# - `etapa`: o último passo da cotação (o tipo do evento da história, que a tela já nomeia);
# - `motivo` e `faltam`: do último `proposta_nao_saiu` ou `algo_mudou_nao_saiu`, quando ele é o último passo (`faltam`
#   são só os nomes dos campos);
# - `resposta`: o que o segurado tocou no "Algo mudou?" (`nada_mudou` ou `mudou`), ou nulo;
# - `premioCentavos` e `seguradora`: da proposta pronta (a melhor oferta);
# - `variacaoPercentual`: a proposta contra o valor do seguro que vence (`valor_centavos`), em %, com uma casa (número; a
#   tela formata). Sem valor anterior ou sem proposta, nulo;
# - `enviadaEm`: quando a proposta saiu (em segundos), sozinha ou pelo clique; `podeEnviar`: há proposta pronta e ela
#   ainda não saiu (o botão "Enviar" do card). O envio que não saiu depois do passo do envio (`proposta_nao_saiu`) desfaz
#   o envio: a proposta volta a poder ser enviada;
# - `incerta`: não se sabe se a proposta chegou (Carteira::Cotacao::Proposta.incerta?): a tela pede para conferir na
#   conversa e oferece "Enviar de novo" (`podeEnviar`).
# Os passos de uma página saem numa consulta só.
class Carteira::Cotacao::Situacao
  TIPOS = %w[cotacao_pedida algo_mudou_nao_saiu respondeu_algo_mudou cliente_respondeu proposta_pedida proposta_nao_saiu
             proposta_pronta proposta_enviada proposta_enviada_sozinha].freeze
  NAO_SAIU = %w[algo_mudou_nao_saiu proposta_nao_saiu].freeze
  ENVIADA = %w[proposta_enviada proposta_enviada_sozinha].freeze
  DO_ENVIO = (ENVIADA + %w[proposta_nao_saiu]).freeze

  # -> a variação em %, com uma casa, ou nil.
  def self.variacao(premio_centavos, valor_centavos)
    return if premio_centavos.nil? || valor_centavos.to_i <= 0

    ((premio_centavos.to_d - valor_centavos) / valor_centavos * 100).round(1).to_f
  end

  def initialize(apolices)
    @apolices = apolices
  end

  # -> { id do seguro => a situação, ou nil }
  def call
    passos = Carteira::ApoliceEvento.where(apolice_id: @apolices.map(&:id), tipo: TIPOS).order(:quando, :id).group_by(&:apolice_id)
    @apolices.to_h { |apolice| [apolice.id, de(apolice, passos.fetch(apolice.id, []))] }
  end

  private

  def de(apolice, passos)
    vigencia = apolice.fim_vigencia.iso8601
    passos = passos.select { |passo| passo.valores.to_h['vigencia'] == vigencia }
    return if passos.empty?

    ultimo = passos.last
    pronta = passos.reverse.find { |passo| passo.tipo == Carteira::Cotacao::Pronta::PRONTA }&.valores
    pronta = pronta.to_h
    { etapa: ultimo.tipo, resposta: resposta(passos) }.merge(do_ultimo(ultimo), da_proposta(apolice, pronta, enviada(passos)))
  end

  # O último passo do envio, quando ele é um envio (e não o envio que não saiu, que deixa enviar de novo).
  def enviada(passos)
    envio = passos.reverse.find { |passo| DO_ENVIO.include?(passo.tipo) }
    envio if ENVIADA.include?(envio&.tipo)
  end

  def resposta(passos)
    passos.reverse.find { |passo| passo.tipo == 'respondeu_algo_mudou' }&.valores&.dig('resposta')
  end

  def do_ultimo(ultimo)
    return { motivo: nil, faltam: [] } unless NAO_SAIU.include?(ultimo.tipo)

    valores = ultimo.valores.to_h
    { motivo: valores['motivo'], faltam: Array(valores['faltam']) }
  end

  def da_proposta(apolice, pronta, envio)
    premio = pronta['premio_centavos']
    incerta = envio.present? && Carteira::Cotacao::Proposta.incerta?(envio)
    enviada = envio unless incerta
    { premioCentavos: premio, seguradora: pronta['seguradora'], variacaoPercentual: self.class.variacao(premio, apolice.valor_centavos),
      enviadaEm: enviada&.quando&.to_i, podeEnviar: pronta.present? && enviada.nil?, incerta: incerta }
  end
end
