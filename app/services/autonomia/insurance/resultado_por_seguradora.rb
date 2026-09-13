# O RESULTADO DE CADA SEGURADORA, GUARDADO NO HANDLE DA COTAÇÃO (fatia 2 do #420).
#
# `InsuranceQuote` chama `unir` em toda consulta ao portal e grava a resposta em
# `InsuranceQuote::Resultado::RESULTADO_KEY`. Quem lê é a ferramenta da Lia (`InsuranceQuoteResult`, por
# `Insurance::ResultadoDaCotacao`), sem ir ao portal.
#
# Uma entrada por código de seguradora, sempre com o nome:
#   - com preço:    { 'nome', 'desfecho' => 'com_preco', 'premio' => { amount, basis, installments } }
#   - sem proposta: { 'nome', 'desfecho' => 'sem_proposta' }, mais 'motivo' => { 'kind', 'text' } só
#                   quando `MotivoDaRecusa.permitido` libera o texto;
#   - sem desfecho: { 'nome', 'desfecho' => 'aguardando' }.
# `auth_required` (credencial da corretora) vira sem proposta e nunca guarda motivo.
module Autonomia::Insurance::ResultadoPorSeguradora
  COM_PRECO = 'com_preco'.freeze
  SEM_PROPOSTA = 'sem_proposta'.freeze
  AGUARDANDO = 'aguardando'.freeze
  # Na união, fica a entrada de desfecho maior; no empate, a que já estava guardada. Dentro de `unir`, um
  # desfecho não volta para `aguardando`, e o preço guardado não é trocado: é o da primeira leitura em que a
  # seguradora cotou, a mesma passada em que o lote dela é emitido. ENTRE PASSADAS CONCORRENTES não vale: o
  # `record_attempt!` de cada uma regrava a chave inteira com a união que ela calculou, e a última escrita
  # fica, mesmo mais velha (a classe de defeito da #418).
  PRECEDENCIA = { AGUARDANDO => 0, SEM_PROPOSTA => 1, COM_PRECO => 2 }.freeze
  # Os campos do prêmio que `PremiumText` lê para escrever o item e que `QuoteOffers#quoted` usa para ordenar.
  CAMPOS_DO_PREMIO = %w[amount basis installments].freeze
  # Os status de oferta sem preço que são desfecho da seguradora (`QuoteOffers::DESFECHOS` sem `quoted`).
  SEM_PRECO = %w[declined auth_required error].freeze
  CREDENCIAL = 'auth_required'.freeze

  module_function

  # -> as entradas guardadas unidas com as desta leitura. Código que esta leitura não listou continua.
  def unir(guardado, ofertas)
    anterior = guardado.is_a?(Hash) ? guardado : {}
    anterior.merge(entradas(ofertas)) { |_codigo, velha, nova| precedencia(nova) > precedencia(velha) ? nova : velha }
  end

  # -> há ao menos uma seguradora com preço guardado?
  def com_preco?(guardado)
    guardado.is_a?(Hash) && guardado.each_value.any? { |entrada| desfecho(entrada) == COM_PRECO }
  end

  # -> { código => entrada } das ofertas de uma leitura. Oferta sem código fica de fora.
  def entradas(ofertas)
    Array(ofertas).each_with_object({}) do |oferta, saida|
      codigo = ::Autonomia::Insurance::QuoteOffers.code(oferta)
      saida[codigo] = entrada(oferta) if codigo.present?
    end
  end

  def entrada(oferta)
    nome = oferta.dig('insurer', 'name').to_s
    if ::Autonomia::Insurance::QuoteOffers.cotada?(oferta)
      return { 'nome' => nome, 'desfecho' => COM_PRECO, 'premio' => oferta['premium'].slice(*CAMPOS_DO_PREMIO) }
    end
    return sem_proposta(nome, oferta) if SEM_PRECO.include?(oferta['status'])

    { 'nome' => nome, 'desfecho' => AGUARDANDO }
  end

  # A entrada sem proposta, com o motivo só quando a oferta não é `auth_required` e a regra libera o texto.
  def sem_proposta(nome, oferta)
    entrada = { 'nome' => nome, 'desfecho' => SEM_PROPOSTA }
    return entrada if oferta['status'] == CREDENCIAL

    texto = ::Autonomia::Insurance::MotivoDaRecusa.permitido(oferta['reason'])
    return entrada if texto.nil?

    entrada.merge('motivo' => { 'kind' => ::Autonomia::Insurance::MotivoDaRecusa::KIND_PERMITIDO, 'text' => texto })
  end

  def desfecho(entrada)
    entrada.is_a?(Hash) ? entrada['desfecho'] : nil
  end

  def precedencia(entrada)
    PRECEDENCIA.fetch(desfecho(entrada), -1)
  end
end
