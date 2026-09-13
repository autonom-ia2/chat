# O QUE A FERRAMENTA DIZ QUANDO RECUSA — textos, rótulos e a forma da recusa (entrega 6).
#
# Separado do comportamento pelo mesmo motivo do `Declaracao`: os textos mudam quando o vocabulário
# muda; `start` e `poll` mudam quando o fluxo muda. E porque a classe passou do teto de linhas ao
# ganhar a terceira recusa (ramo desconhecido).
module Autonomia::Agents::Tools::Native::InsuranceQuote::Recusas
  extend ActiveSupport::Concern

  PEDIDO_DE_JSON = 'O campo `dados` não era um JSON válido. Reenvie como objeto JSON, por ' \
                   'exemplo {"configuracoes":{"marca":"Caloi"}}.'.freeze
  # A LISTA DE RAMOS CONTINUA SENDO DO CÓDIGO (decisão do CEO, 12/09/2026), e por isso ela é uma
  # constante própria: no envio ela é colada na frase que o especialista escreveu, e um modelo que a
  # digitasse de memória listaria um ramo que a corretora não cota.
  RAMOS_QUE_COTO = 'O que eu coto: automóvel, residencial, condomínio, empresarial, aluguel/fiança, ' \
                   'viagem, acidentes pessoais, vida, vida em grupo, celular e bicicleta.'.freeze
  # A abertura, sem a lista: é o que o papel `ramo_desconhecido` recua quando a frase do especialista
  # não passa na peneira.
  RAMO_DESCONHECIDO_ABERTURA = 'Ainda não consigo cotar esse tipo de seguro por aqui.'.freeze
  # Lido pelo MODELO (na conferência): abertura e lista juntas, porque ali não há papel a resolver —
  # o texto volta pelo canal da ferramenta, não pelo do cliente.
  RAMO_DESCONHECIDO = "#{RAMO_DESCONHECIDO_ABERTURA} #{RAMOS_QUE_COTO}".freeze

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
    'vehicle.plate' => 'placa do veículo',
    # O único problema que o chat2you levanta sozinho (`Veiculo#problema_de_zero_km`).
    'vehicle.isZeroKm' => 'se o veículo é zero-quilômetro'
  }.freeze
  FALTA_ALGO = 'Ainda preciso de mais uma informação para fechar a cotação.'.freeze
  # A ABERTURA DO PEDIDO DO QUE FALTA, sem a lista: os RÓTULOS continuam vindo do código (decisão do
  # CEO, 12/09/2026), e é esta frase que o especialista escreve. Termina em dois pontos porque a
  # lista é colada depois dela.
  PEDIDO_DO_QUE_FALTA = 'Para seguir com a cotação, ainda preciso destes dados:'.freeze
  # SEM PLACA, CHASSI OU FIPE NÃO HÁ VEÍCULO PARA COTAR (entrega 2, termo 10). O texto para o
  # MODELO diz o que fazer; o do CLIENTE só pede a placa — o resto é decisão do atendente.
  SEM_VEICULO = 'Não dá para cotar sem identificar o veículo: peça a placa. Se for zero-quilômetro ' \
                'ainda sem placa, o chassi serve; sem os dois, encaminhe para um atendente e diga ' \
                'ao cliente o motivo. Não invente placa nem código FIPE.'.freeze
  SEM_VEICULO_CLIENTE = 'Para cotar, preciso da placa do veículo (ou do chassi, se ele ainda não ' \
                        'tem placa).'.freeze
  # AUTO SEM FORMULÁRIO (entrega 2): a conexão não tem o schema do adapter e o modelo recebeu a
  # ferramenta sem os blocos de auto. Não é o cliente que deve algo; é o atendente que retoma. No
  # envio, o cliente lê `FALHOU`.
  SEM_FORMULARIO = 'O formulário de auto desta conta não está disponível agora (a conexão da ' \
                   'corretora não entregou os campos). Não peça mais dados ao cliente: diga que ' \
                   'não consegue cotar neste momento e encaminhe para um atendente.'.freeze
  LISTA = { two_words_connector: ' e ', last_word_connector: ' e ' }.freeze

  # A FRASE É DO ESPECIALISTA, A LISTA É DO CÓDIGO. Sem rótulo nenhum a traduzir, sai o papel
  # genérico; com rótulos, a abertura que ele escreveu mais os nomes que nós sabemos traduzir.
  def pedido_do_que_falta(faltantes)
    rotulos = faltantes.pluck('campo').filter_map { |campo| ROTULOS[campo.to_s] }.uniq
    return frases[:falta_dado] if rotulos.empty?

    "#{frases[:pedido_do_que_falta]} #{rotulos.to_sentence(**LISTA)}."
  end

  # A FRASE É DO ESPECIALISTA, A LISTA DE RAMOS É DO CÓDIGO. O que o MODELO lê na conferência
  # continua sendo a constante inteira (`RAMO_DESCONHECIDO`): lá não há papel a resolver.
  def ramo_desconhecido_ao_cliente
    "#{frases[:ramo_desconhecido]} #{RAMOS_QUE_COTO}"
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
