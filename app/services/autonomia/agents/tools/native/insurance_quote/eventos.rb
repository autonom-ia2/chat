# OS EVENTOS DA COTAÇÃO E OS FATOS QUE O MODELO LÊ SOBRE CADA UM (PR C).
#
# Até aqui esta ferramenta publicava, pelo motor, as frases que o cliente lia: a constante nossa ou a frase que
# o especialista escrevia no pedido (o nó `frases_ao_cliente`). Agora ela diz o QUE aconteceu e o motor dispara
# o evento (`Tools::Evento`); quem fala é a Lia, num turno de modelo, com a voz dela. Nada daqui chega ao cliente
# como está: é texto para o MODELO.
#
# OS FATOS SÃO DE CLASSE e saem da LINHA (`run.handle`): o evento de falha sai mesmo com o agente apagado. Nunca
# levam dado pessoal: nomes de campo, o motivo que o adapter escreveu, a lista de ramos, o fato da renovação sem
# bônus. O que a busca do segurado achou não entra (ela só roda na conferência, e não deixa nada no handle).
module Autonomia::Agents::Tools::Native::InsuranceQuote::Eventos
  extend ActiveSupport::Concern

  # O motivo da recusa do envio -> o tipo do evento. Formulário indisponível não é dado que a pessoa deve: o evento é
  # `falhou`, com fatos próprios (`SEM_FORMULARIO`), porque pedir de novo daria a mesma recusa. Motivo fora da tabela
  # também é `falhou`.
  EVENTO_DA_RECUSA = {
    'faltam_dados' => 'falta_dado', 'json_invalido' => 'falta_dado', 'sem_veiculo' => 'falta_dado',
    'ramo_desconhecido' => 'ramo_desconhecido', 'formulario_indisponivel' => 'falhou',
    # Conversa 7150: o ramo sem especialista vai para a equipe, como a falha (`RamoSemEspecialista`).
    'ramo_sem_especialista' => 'falhou'
  }.freeze

  # Dito ao modelo junto de todo fato que fala de arquivo enviado: a ordem entre o arquivo e a mensagem, no canal, não
  # é a ordem em que foram gravados.
  ORDEM_DO_ARQUIVO = 'O arquivo pode chegar à pessoa antes ou depois da sua mensagem: não diga em que ponto da conversa ' \
                     'ele está.'.freeze

  FATOS = {
    'cotacao_comecou' => 'A cotação pedida nesta conversa foi recebida e está sendo feita agora. Ainda não se sabe o que as ' \
                         'seguradoras vão responder, e o resultado chega nesta conversa quando ficar pronto.',
    # A ORDEM DO ARQUIVO NÃO É GARANTIDA (chat#641, 25/09/2026). O comparativo é gravado antes da fala da Lia, mas no
    # WhatsApp o upload do PDF atrasa a entrega, e ele chega depois do texto. "Logo acima" aqui virou "está no PDF
    # acima" na fala, e a fala mentia. O fato diz que o arquivo foi enviado, e não onde ele aparece.
    'concluida' => "A cotação terminou, e o comparativo em PDF com as opções acabou de ser enviado nesta conversa. #{ORDEM_DO_ARQUIVO} " \
                   'Os valores de cada seguradora estão com o especialista, que os lê sem cotar de novo.',
    # A LIA RESOLVE SOZINHA (conversa 7057, 24/09/2026): sem o PDF ela mandava a pessoa pedir os valores, e a pessoa
    # ficava sem o que pediu. O turno de evento pode consultar o especialista (`ResponderAoEvento`), e é isso que ela faz.
    'valores_guardados' => 'A cotação terminou com preços, mas o comparativo em PDF não pôde ser enviado. Consulte agora o ' \
                           'especialista do ramo, que lê os valores sem cotar de novo, e mande à pessoa nesta resposta as ' \
                           'opções com seguradora e preço, como ele devolver. Não fale do PDF nem peça que ela peça.',
    # O QUE DEU ERRADO VAI PARA A EQUIPE (decisão do CEO, 23/09/2026). A passagem é do CRM: o gatilho do funil é a
    # própria fala da Lia de que vai encaminhar para alguém da equipe, e aí o CRM atribui a conversa. O prazo esgotado
    # com o comparativo entregue não é erro: a pessoa tem as opções de quem respondeu.
    'falhou' => 'A cotação não pôde ser concluída agora, e nenhuma opção chegou à pessoa. Diga que vai encaminhar para ' \
                'alguém da equipe continuar, sem prazo e sem narrar o que falhou.',
    # A INCERTA NÃO OFERECE REFAZER (revisão da chat#608): a cotação pode existir e já ter sido paga no portal, e o
    # pedido novo não é barrado como repetido (a execução fecha sem entrega). Não se sabe se deu: não se diz que não deu.
    'incerta' => 'Não foi possível confirmar se o pedido chegou às seguradoras, e nenhuma opção chegou à pessoa até ' \
                 'agora. Diga que não conseguiu confirmar e que vai encaminhar para alguém da equipe conferir, sem afirmar ' \
                 'que não deu, sem oferecer cotar de novo e sem prazo.',
    # NINGUÉM TROUXE PROPOSTA (chat#612, decisão do CEO de 23/09/2026): a Lia não fala de recusa nem de motivo com o
    # cliente. O que as seguradoras escreveram vai para a equipe numa nota interna (`NotaDaEquipe`), e a fala dela de
    # que vai encaminhar é o gatilho da passagem no CRM, como em `falhou`.
    'sem_aceitacao' => 'A cotação terminou, e nenhuma seguradora trouxe proposta desta vez. Não fale de recusa, de risco, ' \
                       'de aceitação nem de motivo, e não ofereça cotar de novo. Diga que vai encaminhar para alguém da ' \
                       'equipe olhar a melhor alternativa, sem prazo.',
    'encerrada_por_prazo' => 'A cotação terminou, e o comparativo em PDF com as opções acabou de ser enviado nesta ' \
                             "conversa. #{ORDEM_DO_ARQUIVO} Os valores de cada seguradora estão com o especialista, que " \
                             'os lê sem cotar de novo.'
  }.freeze
  # QUEM FICOU SEM PROPOSTA NÃO É ASSUNTO DO CLIENTE (chat#638, decisão do CEO de 24/09/2026): nem recusa, nem prazo, nem
  # instabilidade. A frase "não responderam a tempo, não foi recusa do risco" que estava nos fatos chegava ao cliente
  # quase igual. Quem fica sabendo é a equipe, pela nota interna (`NotaDaEquipe`).
  SEM_QUEM_FICOU_DE_FORA = 'Não fale de seguradora que ficou sem proposta, nem de prazo, recusa ou motivo.'.freeze
  COM_RESULTADO = %w[concluida valores_guardados encerrada_por_prazo].freeze

  # FORMULÁRIO INDISPONÍVEL (revisão da chat#608): pedir de novo daria a mesma recusa, então não se oferece.
  SEM_FORMULARIO = 'A cotação não pôde ser aberta agora: o formulário deste tipo de seguro não está disponível. Nenhuma ' \
                   'opção chegou à pessoa. Não ofereça cotar de novo agora: diga que vai encaminhar para alguém da ' \
                   'equipe continuar, sem prazo.'.freeze

  # Só em renovação de auto cotada sem a classe de bônus. Sem número e sem promessa de desconto: o quanto o bônus
  # abate é decisão de cada seguradora.
  SEM_BONUS = 'Esta renovação foi cotada sem a classe de bônus da apólice atual: os preços são os de quem faz o primeiro ' \
              'seguro. Com a classe de bônus, que está na apólice, a cotação pode ser refeita, e costuma sair melhor.'.freeze

  # RAMO SEM ESPECIALISTA NO ENVIO (conversa 7150, 26/09/2026): a conferência não rodou e o envio recusou. Quem cuida
  # do seguro é a equipe, e a fala da Lia de que vai encaminhar é o gatilho da passagem no CRM.
  FATOS_SEM_ESPECIALISTA = 'A cotação não foi aberta: este tipo de seguro não é cotado pela IA nesta conta, e quem ' \
                           'cuida dele é a equipe da corretora. Nenhuma opção chegou à pessoa. Não peça dados e não ' \
                           'ofereça cotar: diga que vai encaminhar para alguém da equipe, sem prazo.'.freeze
  # A recusa do envio que vira `falhou` e tem fatos próprios. O resto usa os de `falhou`.
  FATOS_DA_FALHA = { 'formulario_indisponivel' => SEM_FORMULARIO, 'ramo_sem_especialista' => FATOS_SEM_ESPECIALISTA }.freeze

  FALTA_JSON = 'A cotação não foi aberta: os dados do ramo que o especialista mandou não puderam ser lidos. Confira com o ' \
               'especialista o que falta e pergunte à pessoa só o que ninguém disse ainda.'.freeze
  FALTA_PREFIXO = 'A cotação não foi aberta: falta dado que a pessoa precisa dar. O que a conferência apontou:'.freeze

  class_methods do
    # -> os fatos do evento `tipo` desta execução, para o modelo (`Native::Base.fatos_do_evento`), começando pelo
    # seguro e pelo bem (chat#612): com vários bens cotados na conversa, a Lia precisa saber de qual é a notícia.
    def fatos_do_evento(tipo, run)
      "Cotação de #{::Autonomia::Insurance::Faixa.descricao(run)}. #{fatos_do_tipo(tipo.to_s, run.handle.to_h)}"
    end

    private

    def fatos_do_tipo(tipo, handle)
      case tipo
      when 'falta_dado' then fatos_da_falta(handle)
      when 'ramo_desconhecido' then "A cotação não foi aberta. #{self::RAMO_DESCONHECIDO}"
      when 'falhou' then fatos_da_falha(handle)
      else [FATOS[tipo], (SEM_BONUS if COM_RESULTADO.include?(tipo) && handle[self::SEM_BONUS_KEY].present?),
            (SEM_QUEM_FICOU_DE_FORA if COM_RESULTADO.include?(tipo))].compact.join(' ')
      end
    end

    # Formulário indisponível recusaria de novo: não se oferece pedir outra vez.
    def fatos_da_falha(handle)
      FATOS_DA_FALHA.fetch((handle['recusa'] || handle['motivo']).to_s, FATOS['falhou'])
    end

    # A recusa desta versão traz os `problemas` (campo e motivo, como a conferência os produz); a da versão
    # anterior à PR C só traz os nomes em `faltando`, e o texto velho em `pedido`, que não é reaproveitado.
    def fatos_da_falta(handle)
      motivo = (handle['recusa'] || handle['motivo']).to_s
      return FALTA_JSON if motivo == 'json_invalido'
      return "#{FALTA_PREFIXO} #{self::SEM_VEICULO}" if motivo == 'sem_veiculo'

      "#{FALTA_PREFIXO} #{itens_da_falta(handle).join('; ').presence || 'o adapter não disse qual campo'}."
    end

    def itens_da_falta(handle)
      problemas = Array(handle['problemas']).select { |item| item.is_a?(Hash) }
      return problemas.map { |item| "#{campo_com_rotulo(item['campo'])}: #{item['motivo']}" } if problemas.any?

      Array(handle['faltando']).map { |campo| campo_com_rotulo(campo) }
    end

    def campo_com_rotulo(campo)
      self::ROTULOS[campo.to_s] ? "#{campo} (#{self::ROTULOS[campo.to_s]})" : campo.to_s
    end
  end

  private

  # O handle desta execução é o de uma recusa do envio? A versão anterior à PR C gravava o texto em `pedido`.
  def recusa?(handle)
    handle['recusa'].present? || handle['pedido'].present?
  end

  def evento_da_recusa(handle)
    EVENTO_DA_RECUSA.fetch((handle['recusa'] || handle['motivo']).to_s, 'falhou')
  end
end
