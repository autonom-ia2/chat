# Guardar o seguro que a pessoa tem em outra corretora (E6.5, #2899), a partir da leitura do PDF dele e do que a pessoa
# conferiu na tela. O seguro nasce `de_fora: true`, da pessoa da tela, com a corretora em que está e, se ela quis o
# lembrete da renovação, `lembrete_aceito_em`. A rotina da renovação só cria card para ele com o lembrete aceito.
#
# É um gravador próprio, e não o Carteira::Guardar, porque as regras são outras:
# - o Carteira::Guardar procura a apólice pela seguradora e pelo número em toda a conta e completa a que achar (ou recusa
#   por ser de outra pessoa). O seguro de fora não é da carteira da corretora: nunca completa nem muda uma apólice dela;
# - a repetição do seguro de fora é outra (decisão P4): o mesmo contato, já com um seguro de fora da mesma seguradora,
#   do mesmo tipo e com o mesmo fim de vigência. Aí a tela avisa (`seguro_de_fora_repetido`) e nada é criado. O número
#   pode faltar (o PDF de outra corretora nem sempre o traz);
# - o seguro sempre pertence ao contato da tela (nada de casar pessoa pelo documento do PDF), e o telefone e o e-mail
#   achados no PDF não vão para o contato (decisão P5).
#
# O que a pessoa conferiu (`campos`): `tipo`, `seguradora` e `termina` (obrigatórios) e `corretora` (pode ficar vazia).
# Do resto que foi lido entra só o achado com certeza (número, começo, o bem, o ramo como está escrito) e o valor; o valor
# a confirmar (escrito sem "R$") só entra quando a pessoa disse que está certo (`confirmados: ['valor']`). O começo que
# cai depois do fim não entra. `querLembrete` é obrigatório: true ou false.
#
# O PDF do item passa para o seguro (o mesmo arquivo, sem cópia), a história ganha `chegou_de_fora` e `pdf_anexado`, e a
# leitura sai. Tudo numa transação, com o contato travado: dois cliques não criam dois seguros. Nada daqui vai para log.
class Carteira::DeFora::Guardar
  CORRETORA_MAXIMO = 255
  CHEGOU = 'chegou_de_fora'.freeze
  REPETIDO = 'seguro_de_fora_repetido'.freeze
  VALOR = 'valor'.freeze

  def initialize(pessoa, user:)
    @pessoa = pessoa
    @account = pessoa.account
    @user = user
  end

  def call(leitura_id:, quer_lembrete:, campos:, confirmados: [])
    recusar('pedido_invalido') unless [true, false].include?(quer_lembrete) && (Array(confirmados) - [VALOR]).empty?

    dados = do_formulario(campos.to_h.stringify_keys)
    Carteira::Apolice.transaction do
      Contact.where(id: @pessoa.id).lock.load
      item = item_da(leitura_id)
      gravar(item, dados.merge(do_lido(Carteira::ItemLido.new(item), dados, Array(confirmados))), quer_lembrete)
    end
  rescue ActiveRecord::RecordNotUnique
    recusar('apolice_repetida')
  end

  private

  def item_da(leitura_id)
    item = Carteira::DeFora.item_da(@pessoa, leitura_id)
    recusar('leitura_expirou') unless item&.pdf&.attached? && %w[lendo lido].include?(item.estado)
    recusar('leitura_nao_pronta') if item.estado == 'lendo'
    item
  end

  def do_formulario(campos)
    tipo = campos['tipo'].to_s
    seguradora = campos['seguradora'].to_s.strip
    corretora = campos['corretora'].to_s.strip
    recusar(tipo.empty? ? 'falta_tipo' : 'tipo_desconhecido') unless Carteira::Apolice::TIPOS.include?(tipo)
    recusar('falta_seguradora') if seguradora.empty?
    recusar('texto_longo') if [seguradora, corretora].any? { |texto| texto.length > CORRETORA_MAXIMO }

    { tipo: tipo, seguradora: seguradora, seguradora_chave: Carteira::Chave.seguradora(seguradora), fim_vigencia: termina(campos['termina']),
      corretora_de_fora: corretora.presence }
  end

  def termina(valor)
    recusar('falta_termina') if valor.blank?
    Date.iso8601(valor.to_s)
  rescue Date::Error
    recusar('data_invalida')
  end

  def do_lido(lido, dados, confirmados)
    comeca = data_lida(lido.certo('inicio_vigencia'))
    valor = lido.certo('valor_centavos') || (lido.valor('valor_centavos') if confirmados.include?(VALOR))
    do_numero(lido.certo('numero')).merge(bem: lido.certo('bem'), ramo_original: lido.certo('ramo_original'), valor_centavos: valor,
                                          inicio_vigencia: (comeca if comeca && comeca <= dados[:fim_vigencia]))
  end

  # O número e a chave dele andam juntos: o número sem forma de comparação não entra.
  def do_numero(numero)
    chave = Carteira::Chave.numero(numero).presence if numero
    chave ? { numero: numero, numero_chave: chave } : { numero: nil, numero_chave: nil }
  end

  def data_lida(valor)
    Date.iso8601(valor.to_s) if valor.present?
  rescue Date::Error
    nil
  end

  def gravar(item, dados, quer_lembrete)
    recusar(REPETIDO) if repetido?(dados)

    apolice = Carteira::Apolice.create!(dados.merge(account: @account, contact: @pessoa, origem: 'pdf', de_fora: true,
                                                    lembrete_aceito_em: (Time.current if quer_lembrete)))
    apolice.eventos.create!(tipo: CHEGOU, quando: Time.current, user: @user, valores: { lembrete: quer_lembrete })
    passar_o_pdf(item, apolice)
    item.leitura.destroy!
    apolice
  end

  def repetido?(dados)
    Carteira::Apolice.exists?(account_id: @account.id, contact_id: @pessoa.id, de_fora: true, tipo: dados[:tipo],
                              seguradora_chave: dados[:seguradora_chave], fim_vigencia: dados[:fim_vigencia])
  end

  def passar_o_pdf(item, apolice)
    apolice.pdf = item.pdf.blob
    apolice.save!
    item.pdf.detach
    apolice.eventos.create!(tipo: Carteira::Pdf::ANEXADO, quando: Time.current, user: @user)
  end

  # Só o código: sem a causa, que pode ser a mensagem do banco com o número da apólice.
  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
