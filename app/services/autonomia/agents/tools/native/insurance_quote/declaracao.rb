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
    # O BEM DESTA COTAÇÃO (chat#612). Cada bem é uma cotação, e elas correm em paralelo. Quem decide se o pedido é o
    # mesmo bem (recotar, corrigir) ou outro é o modelo, pelo nome que ele dá: nenhum código compara placa ou endereço.
    { 'name' => 'item', 'type' => 'string',
      'description' => 'Nome curto do bem desta cotação, como o cliente o chama: o carro pelo modelo (a placa só se ' \
                       'houver dois do mesmo modelo), o imóvel pelo que o distingue. Para recotar ou corrigir um bem ' \
                       'que já tem cotação nesta conversa, repita exatamente o nome que ele já tem; bem diferente, nome ' \
                       'novo. Dois bens são duas chamadas, cada uma com o seu nome.' },
    # O QUE O CLIENTE PEDIU PARA ESTE BEM (item 6 da auditoria de voz, 26/09/2026). Não vai ao portal (`QuoteInput`
    # só lê os grupos e os campos que nomeia) nem à identidade do pedido (`Insurance::Pedido`, que lê a entrada do
    # adapter): fica na execução, e o aviso de fim da cotação o conta à Lia (`Eventos#fatos_do_pedido`), para ela
    # dizer algo que só vale para esta cotação.
    { 'name' => 'pedido_que_entrou', 'type' => 'string', 'required' => false,
      'description' => 'O que você pediu às seguradoras para este bem a partir do que o cliente pediu, em poucas ' \
                       'palavras. Nulo se ele não pediu nada além de cotar.' },
    { 'name' => 'pedido_que_nao_coube', 'type' => 'string', 'required' => false,
      'description' => 'O que ele pediu para este bem e não coube, com o motivo em linguagem de gente. Nulo se tudo ' \
                       'coube.' },
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
              'outros ramos, informe o que o cliente já deu em dados; se faltar algo, a ' \
              'ferramenta responde exatamente o que perguntar, sem consumir cotação.'.freeze

  # A DESCRIÇÃO DO ESPECIALISTA DE UM RAMO COM FORMULÁRIO (revisão da chat#592). Ele não recebe `dados`, e a
  # DESCRICAO acima mandaria escrever nele: o modelo tentaria um campo que não existe, ou hesitaria. Esta diz o que o
  # formulário dele é, sem nome de campo digitado aqui.
  DESCRICAO_COM_FORMULARIO = 'Cota o seguro deste ramo nas seguradoras que esta corretora atende. Preencha os ' \
                             'blocos com o que o cliente contou, cada campo explicado nele; rua, bairro e cidade ' \
                             'o sistema busca pelo CEP. O que ninguém disse fica nulo. Se faltar algo, a ' \
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
  #
  # NEM O QUE DIZER AO CLIENTE (23/09/2026). A versão anterior mandava "diga ao cliente que está cuidando e que volta
  # aqui assim que tiver notícia". O especialista, que não fala com o cliente, escrevia essa frase para a Lia, e ela a
  # repassava com os dados do pedido: "Peguei o seguro do carro, placa tal, no CEP tal. Volto com as opções por aqui",
  # igual a cada cotação da conversa. Agora o texto diz o FATO e o que devolver ao atendente; a fala é dela.
  #
  # FATOS, NÃO FALA (item 9 da auditoria de voz, 26/09/2026): o especialista devolve ao atendente as partes do retorno
  # dele (`QuoteAgent::RetornoDoEspecialista`), e é o atendente quem escreve. O aceite diz o mesmo, com as mesmas
  # partes, para a regra mais perto da ação não contradizer o manual.
  ACEITA = 'A cotação abriu e está sendo feita. O resultado chega sozinho nesta conversa, sem ninguém pedir. ' \
           'Devolva ao atendente, nos seus fatos, o que ele ainda não sabe e o cliente precisa ouvir: uma troca que ' \
           'você fez, uma ressalva, o que foi pedido às seguradoras e o que ficou de fora. Não repita os dados do pedido, não ' \
           'escreva frase pronta para o cliente e não afirme que já chegou às seguradoras (ainda não chegou). Sem ' \
           'vocabulário de sistema ("em conferência", "processando", "em análise") e sem inventar valor, prazo ou ' \
           'nome de seguradora.'.freeze

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

    # Sem `dados` entre os parâmetros, o formulário é o do ramo: a descrição não pode mandar o modelo escrever nele.
    # Auto sempre leva `dados` (COMUNS), então a descrição de auto não muda.
    def description_for(parametros)
      parametros.any? { |param| param['name'] == 'dados' } ? DESCRICAO : DESCRICAO_COM_FORMULARIO
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
    # OS RAMOS EM QUE A SEGURADORA SÓ CALCULA COM A ATIVIDADE ESCOLHIDA NA LISTA DELA (chat#641). A atividade não
    # é campo do formulário do adapter (vive fora de `configuracoes`): ela entra aqui, como lista de objetos.
    RAMOS_COM_ATIVIDADE = %w[empresarial].freeze
    ATIVIDADES = {
      'name' => 'atividades', 'type' => 'array',
      'description' => 'A atividade da empresa escolhida em cada seguradora, a partir da busca de atividade. Uma ' \
                       'entrada por seguradora escolhida, com seguradora, key e value exatamente como a busca ' \
                       'devolveu. Seguradora sem opção que corresponda fica de fora da lista.',
      'items' => { 'properties' => [
        { 'name' => 'seguradora', 'type' => 'string', 'description' => 'O código da seguradora, como a busca devolveu.' },
        { 'name' => 'key', 'type' => 'string', 'description' => 'A key da opção escolhida, como a busca devolveu.' },
        { 'name' => 'value', 'type' => 'string', 'description' => 'O value da opção escolhida, como a busca devolveu.' }
      ] }
    }.freeze

    def params_for(agent, especialista: nil)
      ramo = ::Autonomia::Insurance::QuoteAgent::Builder.ramo_do_especialista(especialista) || self::AUTO
      return params + ::Autonomia::Insurance::Parametros.de_auto(schema_de_auto(agent)) if ramo == self::AUTO

      formulario = formulario_do_ramo(agent, ramo)
      # Com o formulário, `dados` sai: ele é o JSON solto que o formulário substitui, e a instrução
      # dele ("mande {} na primeira vez") é a rodada a mais que a fase 2 existe para tirar. Sem o
      # formulário, fica, e o ramo cota pelo caminho de antes.
      base = formulario.empty? ? params : params.reject { |param| param['name'] == 'dados' } + formulario
      RAMOS_COM_ATIVIDADE.include?(ramo) ? base + [ATIVIDADES] : base
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
