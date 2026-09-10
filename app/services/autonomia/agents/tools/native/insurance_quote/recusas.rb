# O QUE A FERRAMENTA DIZ QUANDO RECUSA — textos, rótulos e a forma da recusa (entrega 6).
#
# Separado do comportamento pelo mesmo motivo do `Declaracao`: os textos mudam quando o vocabulário
# muda; `start` e `poll` mudam quando o fluxo muda. E porque a classe passou do teto de linhas ao
# ganhar a terceira recusa (ramo desconhecido).
module Autonomia::Agents::Tools::Native::InsuranceQuote::Recusas
  extend ActiveSupport::Concern

  PEDIDO_DE_JSON = 'O campo `dados` não era um JSON válido. Reenvie como objeto JSON, por ' \
                   'exemplo {"configuracoes":{"marca":"Caloi"}}.'.freeze
  # Lido pelo modelo (na conferência) e pelo cliente (no envio): sem vocabulário de sistema.
  RAMO_DESCONHECIDO = 'Ainda não consigo cotar esse tipo de seguro por aqui. O que eu coto: ' \
                      'automóvel, residencial, condomínio, empresarial, aluguel/fiança, viagem, ' \
                      'acidentes pessoais, vida, vida em grupo, celular e bicicleta.'.freeze

  # ESTE TEXTO É LIDO PELO CLIENTE, e não pelo modelo. O comentário anterior aqui dizia o oposto —
  # "nomes de campo crus de propósito: quem traduz é o especialista" — e descrevia um tradutor que
  # não existe neste caminho: a recusa vira `deliveries`, e `Progress` afirma que deliveries são
  # "textos DESTINADOS AO CLIENTE". Em 08/09/2026 um cliente leu `insured.document` no WhatsApp,
  # junto com "chame a ferramenta de novo", que é instrução para o modelo.
  #
  # Traduzimos SÓ o que a própria ferramenta coleta — os caminhos que `QuoteInput` monta a partir
  # dos parâmetros dela. Para o resto (campo de ramo que veio dentro de `dados`) NÃO inventamos
  # rótulo: dizer "valorMercado" seria vazar de novo, e chutar um nome em português seria adivinhar
  # o que o portal chama de quê. Aí a frase fica genérica, e quem pergunta é o modelo no turno
  # seguinte — ele lê esta entrega como turno `assistant` no histórico.
  # Rótulo SEM artigo: ele entra numa lista, e "preciso de o CPF" é o que sai quando o artigo vem
  # colado no rótulo.
  ROTULOS = {
    'insured.document' => 'CPF do titular', 'segurado.cpfCnpj' => 'CPF do titular',
    'insured.name' => 'nome do titular', 'segurado.nome' => 'nome do titular',
    'address.zipCode' => 'CEP', 'segurado.cep' => 'CEP',
    'address.number' => 'número do endereço', 'segurado.numero' => 'número do endereço',
    'vehicle.plate' => 'placa do veículo'
  }.freeze
  FALTA_ALGO = 'Ainda preciso de mais uma informação para fechar a cotação.'.freeze
  # SEM PLACA, CHASSI OU FIPE NÃO HÁ VEÍCULO PARA COTAR (entrega 2, termo 10). O texto para o
  # MODELO diz o que fazer; o do CLIENTE só pede a placa — o resto é decisão do atendente.
  SEM_VEICULO = 'Não dá para cotar sem identificar o veículo: peça a placa. Se for zero-quilômetro ' \
                'ainda sem placa, o chassi serve; sem os dois, encaminhe para um atendente e diga ' \
                'ao cliente o motivo. Não invente placa nem código FIPE.'.freeze
  SEM_VEICULO_CLIENTE = 'Para cotar, preciso da placa do veículo (ou do chassi, se ele ainda não ' \
                        'tem placa).'.freeze
  LISTA = { two_words_connector: ' e ', last_word_connector: ' e ' }.freeze

  def pedido_do_que_falta(faltantes)
    rotulos = faltantes.pluck('campo').filter_map { |campo| ROTULOS[campo.to_s] }.uniq
    return FALTA_ALGO if rotulos.empty?

    "Para seguir com a cotação, ainda preciso destes dados: #{rotulos.to_sentence(**LISTA)}."
  end

  # O QUE O MODELO LÊ NA CONFERÊNCIA (entrega 2): o campo e o motivo, como o adapter os escreveu —
  # em português, com a regra ("renovação exige a seguradora anterior…"). É o modelo quem traduz
  # para o cliente; dar a ele o nome do campo é o que o deixa preencher certo na volta. O texto
  # para o CLIENTE (`pedido_do_que_falta`) continua sendo o do envio.
  def conferencia_para_o_modelo(problemas)
    itens = problemas.map { |p| "#{p['campo']} — #{p['motivo']}" }
    "Antes de cotar, corrija ou complete: #{itens.join('; ')}"
  end

  private

  # A recusa VIRA ENTREGA, e não falha. O agente precisa receber o texto para perguntar ao cliente;
  # `failed` mandaria a mensagem genérica de erro e a conversa morreria sem ninguém saber o que
  # faltava. O `poll` reconhece o handle com `pedido` e entrega na primeira passada.
  #
  # O REGISTRO (conversa, agente, o que faltou) é feito por quem chama o `start` — o `AsyncRunJob` —,
  # porque esta ferramenta não conhece a conversa, de propósito. `faltando` viaja no handle para
  # isso: só NOMES de campo, nunca valores.
  def recusa(motivo, texto, faltando:)
    { 'pedido' => texto, 'motivo' => motivo, 'faltando' => faltando }
  end

  def conferencia(motivo, texto, faltando)
    ::Autonomia::Agents::Tools::Native::Conferencia.new(texto: texto, faltando: faltando, motivo: motivo)
  end

  def campos(faltantes)
    faltantes.pluck('campo').map(&:to_s).uniq
  end
end
