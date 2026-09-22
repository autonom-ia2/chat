# O QUE A FERRAMENTA DIZ QUANDO RECUSA — textos, rótulos e a forma da recusa (entrega 6).
#
# Separado do comportamento pelo mesmo motivo do `Declaracao`: os textos mudam quando o vocabulário
# muda; `start` e `poll` mudam quando o fluxo muda. E porque a classe passou do teto de linhas ao
# ganhar a terceira recusa (ramo desconhecido).
module Autonomia::Agents::Tools::Native::InsuranceQuote::Recusas
  extend ActiveSupport::Concern

  PEDIDO_DE_JSON = 'O campo `dados` não era um JSON válido. Reenvie como objeto JSON, por ' \
                   'exemplo {"configuracoes":{"marca":"Caloi"}}.'.freeze
  # Lido pelo MODELO (na conferência e nos fatos do evento `ramo_desconhecido`): o texto volta pelo canal da
  # ferramenta, nunca pelo do cliente. A lista de ramos é do código: um modelo que a digitasse de memória
  # listaria um ramo que a corretora não cota.
  RAMO_DESCONHECIDO = 'Esse tipo de seguro não é cotado por aqui. Os ramos que esta corretora cota: automóvel, residencial, ' \
                      'condomínio, empresarial, aluguel/fiança, viagem, acidentes pessoais, vida, vida em grupo, celular e bicicleta.'.freeze

  # O NOME EM PORTUGUÊS DE CADA CAMPO QUE A PRÓPRIA FERRAMENTA COLETA, para o MODELO (os fatos do evento
  # `falta_dado`, `Eventos`): ele lê "insured.birthDate (data de nascimento do titular)" e pergunta à pessoa com
  # as palavras dele. Desde a PR C nenhum rótulo daqui chega ao cliente como está.
  #
  # Só o que `QuoteInput` monta a partir dos parâmetros da ferramenta. Para o resto (campo de ramo que veio
  # dentro de `dados`) NÃO inventamos rótulo: chutar um nome em português seria adivinhar o que o portal
  # chama de quê. Aí o modelo lê o nome do campo e o motivo do adapter.
  ROTULOS = {
    'insured.document' => 'CPF do titular', 'segurado.cpfCnpj' => 'CPF do titular',
    'insured.name' => 'nome do titular', 'segurado.nome' => 'nome do titular',
    'address.zipCode' => 'CEP', 'segurado.cep' => 'CEP',
    'address.number' => 'número do endereço', 'segurado.numero' => 'número do endereço',
    'vehicle.plate' => 'placa do veículo',
    # Os dois que a consulta de CPF preenche quando acha a pessoa, e que o `quote/start` recusa quando
    # não acha (#470).
    'insured.birthDate' => 'data de nascimento do titular', 'insured.gender' => 'sexo do titular',
    # O único problema que o chat2you levanta sozinho (`Veiculo#problema_de_zero_km`).
    'vehicle.isZeroKm' => 'se o veículo é zero-quilômetro'
  }.freeze
  # SEM PLACA, CHASSI OU FIPE NÃO HÁ VEÍCULO PARA COTAR (entrega 2, termo 10). Texto para o MODELO: na
  # conferência e nos fatos do evento `falta_dado`.
  SEM_VEICULO = 'Não dá para cotar sem identificar o veículo: peça a placa. Se for zero-quilômetro ' \
                'ainda sem placa, o chassi serve; sem os dois, encaminhe para um atendente e diga ' \
                'ao cliente o motivo. Não invente placa nem código FIPE.'.freeze
  # AUTO SEM FORMULÁRIO (entrega 2): a conexão não tem o schema do adapter e o modelo recebeu a
  # ferramenta sem os blocos de auto. Não é o cliente que deve algo; é o atendente que retoma. No
  # envio, o evento é `falhou`.
  SEM_FORMULARIO = 'O formulário de auto desta conta não está disponível agora (a conexão da ' \
                   'corretora não entregou os campos). Não peça mais dados ao cliente: diga que ' \
                   'não consegue cotar neste momento e encaminhe para um atendente.'.freeze
  # CONEXÃO FORA (chat#585): em 21/09/2026 a conexão ficou offline por nove horas ("Sessões lotadas" no portal) e a
  # cotação pedida nesse intervalo era aceita para morrer depois de 23 tentativas. Recusada antes, nada é aberto.
  CONEXAO_FORA = 'A corretora está sem conexão com o portal de cotação neste momento, e a cotação não foi aberta. ' \
                 'Não peça mais dados ao cliente e não diga que vai cotar: diga que não consegue cotar agora, sem ' \
                 'falar de portal, login ou sistema, e ofereça chamar uma pessoa da equipe.'.freeze
  # O QUE O MODELO LÊ NA CONFERÊNCIA (entrega 2): o campo e o motivo, como o adapter os escreveu —
  # em português, com a regra ("renovação exige a seguradora anterior…"). É o modelo quem traduz
  # para o cliente; dar a ele o nome do campo é o que o deixa preencher certo na volta.
  def conferencia_para_o_modelo(problemas)
    itens = problemas.map { |p| "#{p['campo']} — #{p['motivo']}" }
    "Antes de cotar, corrija ou complete: #{itens.join('; ')}"
  end

  private

  # A recusa do envio VIRA EVENTO, e não falha (PR C). O `poll` reconhece o handle com `recusa` e devolve
  # `done` com o evento da recusa (`Eventos#evento_da_recusa`); a Lia fala com a pessoa a partir dos fatos
  # (`Eventos.fatos_do_evento`). `failed` mandaria o evento genérico de falha, e ninguém saberia o que faltava.
  #
  # O REGISTRO (conversa, agente, o que faltou) é feito por quem chama o `start` — o `AsyncRunJob` —,
  # porque esta ferramenta não conhece a conversa, de propósito. `faltando` e `problemas` viajam no handle
  # para isso e para os fatos: NOMES de campo e o motivo do adapter, nunca valores.
  def recusa(motivo, faltando:, problemas: [])
    { 'recusa' => motivo, 'faltando' => faltando,
      'problemas' => problemas.map { |p| { 'campo' => p['campo'].to_s, 'motivo' => p['motivo'].to_s } } }
  end

  def conferencia(motivo, texto, faltando, recusados: {})
    ::Autonomia::Agents::Tools::Native::Conferencia.new(texto: texto, faltando: faltando, motivo: motivo, recusados: recusados)
  end

  def conferencia_do_que_falta(faltantes)
    conferencia('faltam_dados', conferencia_para_o_modelo(faltantes), campos(faltantes), recusados: recusados(faltantes))
  end

  # O valor que a entrada levou em cada COBERTURA recusada (#585), para o registro dizer o que foi mandado.
  def recusados(faltantes)
    faltantes.filter_map do |problema|
      campo = problema['campo'].to_s
      # Descida que não levanta: um nível que não é Hash vira nil. Uma exceção aqui cairia no `rescue` do
      # `precheck`, e a conferência aceitaria uma cotação paga com valor inválido.
      [campo, campo.split('.').reduce(entrada.to_h) { |nivel, chave| nivel.is_a?(Hash) ? nivel[chave] : nil }] if campo.start_with?('coverage.')
    end.to_h
  end

  def campos(faltantes)
    faltantes.pluck('campo').map(&:to_s).uniq
  end
end
