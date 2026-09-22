# O CONTRATO COM O MODELO — o que ele lê para decidir usar a ferramenta, e o que pode escrever.
#
# Separado do comportamento porque são coisas que mudam por motivos diferentes: a descrição e os
# parâmetros mudam quando o vocabulário do agente muda; `start` e `poll` mudam quando o fluxo de
# cotação muda. Juntos, cada ajuste de texto abria o arquivo que decide o que vai para o cliente.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Declaracao
  extend ActiveSupport::Concern

  # `dados` viaja como TEXTO JSON, e não como objeto. O schema de função exige `strict` com
  # `additionalProperties: false`, e um objeto de forma livre não tem como ser declarado ali — cada
  # ramo tem os seus campos, que é o ponto desta ferramenta. Texto é o único tipo que atravessa; a
  # ferramenta parseia e diz com clareza quando o JSON não presta.
  COMUNS = [
    { 'name' => 'produto', 'type' => 'string',
      'description' => 'Ramo a cotar: auto, residencial, condominio, empresarial, ' \
                       'fianca_locaticia, viagem, acidentes_pessoais, vida, vida_global, celular ' \
                       'ou bike.' },
    { 'name' => 'cpf', 'type' => 'string', 'required' => false,
      'description' => 'CPF ou CNPJ do segurado, só números ou formatado.' },
    { 'name' => 'nome', 'type' => 'string', 'required' => false,
      'description' => 'Nome do segurado, se o cliente já informou.' },
    { 'name' => 'cep', 'type' => 'string', 'required' => false,
      'description' => 'CEP: onde o carro dorme (auto) ou onde fica o imóvel.' },
    { 'name' => 'numero', 'type' => 'string', 'required' => false,
      'description' => 'Número do endereço, se o cliente informou.' },
    { 'name' => 'dados', 'type' => 'string', 'required' => false,
      'description' => 'JSON com o que o cliente informou nos ramos que não são auto, usando os ' \
                       'nomes de campo que a ferramenta pedir. Exemplo para bike: ' \
                       '{"configuracoes":{"marca":"Caloi","valorMercado":8000}}. Mande {} na ' \
                       'primeira vez para descobrir o que perguntar.' }
  ].freeze

  # AUTO NÃO TEM PARÂMETRO DIGITADO AQUI (entrega 2 do Agente de Cotação). Os ~90 campos de auto
  # vêm do `quote/schema` do adapter, guardado na conexão da conta na sincronização, e entram
  # aninhados por grupo (`vehicle: { plate }`) com a descrição em português que o adapter escreveu.
  # Ver `Insurance::Parametros` e `params_for` abaixo. Até 10/09/2026 eram quatro campos à mão —
  # placa, renovação, bônus, sinistros —, e a renovação saía sem a seguradora anterior porque não
  # havia onde escrevê-la: 17 recusas, zero preço.

  DESCRICAO = 'Cota seguro de AUTOMÓVEL, RESIDENCIAL, CONDOMÍNIO, EMPRESARIAL, ALUGUEL/FIANÇA, ' \
              'VIAGEM, ACIDENTES PESSOAIS, VIDA, VIDA EM GRUPO, CELULAR ou BICICLETA nas ' \
              'seguradoras que esta corretora atende. Para auto, precisa do CPF, da placa e do ' \
              'CEP de pernoite; o resto do que o cliente contou vai nos blocos (vehicle, ' \
              'coverage, quotation…), cada campo explicado nele; a ferramenta consulta a placa por ' \
              'conta própria. Nos ' \
              'outros ramos, informe o que o cliente já deu em `dados`; se faltar algo, a ' \
              'ferramenta responde exatamente o que perguntar, sem consumir cotação.'.freeze

  # NÃO PROMETA O QUE AINDA NÃO ACONTECEU. Este texto volta ao modelo em `Bound#accept_async`, que
  # roda ANTES de qualquer conferência: nada foi enviado a seguradora nenhuma ainda, e o pedido pode
  # ser recusado logo em seguida por falta de dado, por conexão fora do ar ou por prazo. Quando ele
  # dizia "Cotação enviada às seguradoras", o agente anunciava sucesso e cinco segundos depois se
  # desmentia na frente do cliente — em 08/09/2026, com estas duas mensagens seguidas.
  # NÃO ENTREGUE AS PALAVRAS, SÓ O QUE TRANSMITIR. A versão anterior dizia "recebido e em
  # conferência" — e o modelo devolveu ao cliente "a cotação está em conferência e não há preços
  # disponíveis neste momento". Vocabulário de sistema posto na boca dele, que é exatamente o que a
  # instrução do agente proíbe em §4. Ele obedeceu o exemplo, não a regra.
  ACEITA = 'Você recebeu o pedido e já está cuidando dele. Diga isso ao cliente com as SUAS ' \
           'palavras, e que você volta aqui assim que tiver notícia. NÃO afirme que já foi ' \
           'enviada às seguradoras (ainda não foi), não use vocabulário de sistema — "em ' \
           'conferência", "processando", "em análise", "não há dados disponíveis" — e não invente ' \
           'valores, prazos nem nomes de seguradora.'.freeze

  # AS FRASES AO CLIENTE SAÍRAM DAQUI (PR C). Havia seis constantes de desfecho e o nó `frases_ao_cliente`, em que
  # o especialista escrevia no pedido as doze frases que o motor publicava. Agora o motor dispara um evento e a
  # Lia fala num turno de modelo (`Tools::Evento`); o que esta ferramenta diz é para o MODELO (`Eventos`).

  # `module ClassMethods` em vez de `class_methods do`: mesmo efeito no concern, e um módulo não
  # tem o teto de linhas de bloco — o catálogo de textos cresce a cada ramo.
  module ClassMethods
    def slug
      'cotar_seguro'
    end

    def tool_name
      'Cotar seguro'
    end

    # Cotar leva minutos: o turno não pode esperar. `start` submete e volta com o id; `poll` consulta.
    def async?
      true
    end

    def description
      DESCRICAO
    end

    def params
      COMUNS
    end

    # O FORMULÁRIO DE UMA CONTA: os campos comuns a todo ramo + os de auto, gerados do schema que o
    # adapter entregou na sincronização da conexão (`Connection#quote_schema`). Sem conexão pronta
    # ou sem agente (catálogo, specs) fica só o comum. Sem schema com conexão pronta (adapter mudo
    # na sincronização e agora) TAMBÉM fica só o comum — e a própria ferramenta recusa auto com
    # `formulario_indisponivel` (`Veiculo#sem_formulario?`), em vez de cobrar placa do cliente por
    # um bloco que o modelo nunca recebeu.
    #
    # UM FORMULÁRIO POR ESPECIALISTA (chat#591, decisão da receita de ramo, fase 2). O ramo vem do
    # especialista que monta o turno (`Builder.ramo_do_especialista`, a chave `ramo` de
    # `ESPECIALISTAS`), e não do que o modelo escreve em `produto`: o formulário existe antes de o
    # modelo escrever qualquer coisa. Sem especialista, ou num que a Autonom.ia não mantém, o ramo é
    # auto, e o formulário é o de sempre. Um formulário com todos os ramos multiplicaria o que o
    # modelo lê a cada turno por onze.
    def params_for(agent, especialista: nil)
      ramo = ::Autonomia::Insurance::QuoteAgent::Builder.ramo_do_especialista(especialista) || self::AUTO
      return params + ::Autonomia::Insurance::Parametros.de_auto(schema_de_auto(agent)) if ramo == self::AUTO

      formulario = formulario_do_ramo(agent, ramo)
      # Com o formulário, `dados` sai: ele é o JSON solto que o formulário substitui, e a instrução
      # dele ("mande {} na primeira vez") é a rodada a mais que a fase 2 existe para tirar. Sem o
      # formulário, fica, e o ramo cota pelo caminho de antes.
      formulario.empty? ? params : params.reject { |param| param['name'] == 'dados' } + formulario
    end

    # CAMPO SEM DESCRIÇÃO QUEBRA, NÃO SOME. O formulário inteiro é recusado (`FormularioInvalido`), e
    # não só o campo: um formulário sem o campo esconderia do modelo um dado que o adapter pede, e
    # ninguém veria. Recusado, o ramo volta ao `dados` e o erro fica no log com o ramo e os campos.
    # Levantar daqui derrubaria a montagem do turno inteiro, e o especialista ficaria mudo (modo A8).
    # Quem pega antes da produção é a `parametros_do_ramo_spec`, sobre o schema gerado do adapter.
    def formulario_do_ramo(agent, ramo)
      ::Autonomia::Insurance::Parametros.do_ramo(schema_do_ramo(agent, ramo))
    rescue ::Autonomia::Insurance::Parametros::FormularioInvalido => e
      Rails.logger.error("[autonomia][insurance] formulario do ramo recusado: #{e.message}")
      []
    end

    def schema_de_auto(agent)
      schema_do_ramo(agent, self::AUTO)
    end

    def schema_do_ramo(agent, produto)
      return nil if agent.nil?

      connection = ::Autonomia::Insurance::Connection.for_account(agent.account).find(&:ready?)
      connection && schema_da_conexao(connection, produto)
    end

    # O schema guardado na conexão ou, faltando, o que o adapter responder AGORA — e fica guardado.
    # Conexão sincronizada antes desta versão não tem o schema: sem isto o formulário ficaria sem
    # auto até a próxima sincronização. Adapter mudo é nil, e a próxima montagem tenta de novo. O
    # custo é de 10 s de LEITURA por tentativa (`CONFERENCIA_TIMEOUT`, sem contar conexão e lock), e
    # num mesmo atendimento sem schema há até duas: na montagem do formulário e na conferência
    # (`Veiculo#sem_formulario?`). Só enquanto não há schema guardado.
    def schema_da_conexao(connection, produto = self::AUTO)
      connection.quote_schema(produto) || buscar_e_guardar_schema(connection, produto)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][insurance] schema de #{produto} indisponivel connection=#{connection.id} #{e.class}")
      nil
    end

    def buscar_e_guardar_schema(connection, produto)
      schema = ::Autonomia::Insurance::Connector.client.quote_schema(provider: connection.provider, product: produto)
      connection.merge_metadata!('quote_schemas' => connection.metadata.to_h['quote_schemas'].to_h.merge(produto => schema))
      schema
    end

    # Ferramenta que depende de recurso não configurado não deve nem aparecer no prompt: melhor não
    # oferecer do que oferecer e falhar na frente do cliente.
    def available_for?(agent)
      return false unless ::Autonomia::Insurance::Config.enabled?(agent.account)

      ::Autonomia::Insurance::Connection.for_account(agent.account).any?(&:ready?)
    rescue StandardError
      false
    end

    def accepted_message
      ACEITA
    end
  end
end
