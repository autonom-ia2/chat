# A gravação de uma busca no conector (E7, #2900), no Carteira::Conector::GravarJob: cada registro pronto vira seguro na
# carteira, BLOCO por execução (o job se reagenda até acabar). A primeira busca chega aqui pelo "Trazer" do Conferir; a de
# todo dia, sozinha.
#
# Os registros vão em ORDEM (ORDEM): pelo começo da vigência (sem começo, por último), depois pela referência, depois pela
# data do endosso (sem endosso primeiro). Assim o termo velho de uma apólice entra antes do novo, e a renovação se liga a
# ele. Da mesma referência e do mesmo começo (a apólice e os endossos dela), só o ÚLTIMO nessa ordem é gravado: o endosso
# mais novo fica por cima, venham na ordem que vierem, e os de antes ficam `repetido` (cada registro do Agger traz o seguro
# inteiro). Sem isso, a busca de todo dia que traz de novo a apólice e o endosso voltaria o valor e o poria outra vez.
#
# Para cada registro, numa transação só dele:
# 1. a pessoa (Carteira::Conector::PessoaDoRegistro): a do seguro que já tem a mesma referência; senão, a da conta que tem
#    o CPF/CNPJ do segurado (decisão R1); senão, a que nasce agora com o nome do segurado. Nunca pelo nome. A que nasce
#    fica marcada no item (o Desfazer só tira quem a busca criou) e não leva o e-mail que já é de outra pessoa da conta;
# 2. o seguro, SEMPRE pelo gravador único (Carteira::Guardar, origem `conector`, a mais forte, com a leitura e com
#    `origem_ref` = a referência do registro). A mesma referência de novo atualiza, nunca duplica;
# 3. o seguro novo pode ser a renovação de um que já estava na carteira (feita fora do sistema): ele se liga ao anterior
#    pelo caminho de sempre (Carteira::Renovacao::Ligar#sozinha), e o card de renovação do anterior fecha;
# 4. o registro que não muda nada (o gravador devolve `igual` e nenhum passo desta busca ficou no seguro) fica `igual`,
#    SEM se ligar ao seguro: senão o Desfazer da busca, do lote de PDFs ou da planilha que criou o seguro acharia esta
#    busca apontando para ele e o deixaria na carteira. Ele não conta como seguro trazido (o histórico conta só os
#    novos e os que mudaram).
# O registro sem pessoa (sem documento e sem seguro guardado com a referência), recusado pelo gravador ou com um erro
# inesperado vira `nao_entrou` (o motivo é só contado) e os outros seguem.
#
# No fim, uma passada da renovação nos seguros que a busca criou e ficaram sem anterior (a anterior chegou depois, na mesma
# busca), e a leitura fica `trazida`, com quantos seguros e quantas pessoas entraram; os PDFs vêm depois, num job próprio
# (Carteira::Conector::PdfsJob). Rodar de novo continua de onde parou. Nada daqui vai para log além de ids.
class Carteira::Conector::Gravar
  BLOCO = 100
  LIDO = Carteira::Conector::Ler::LIDO
  IGUAL = 'igual'.freeze
  REPETIDO = 'repetido'.freeze
  ORDEM = Arel.sql(
    "carteira_leitura_itens.campos ->> 'inicio_vigencia' ASC NULLS LAST, carteira_leitura_itens.campos ->> 'ref' ASC, " \
    "carteira_leitura_itens.campos ->> 'endosso_data' ASC NULLS FIRST, carteira_leitura_itens.campos ->> 'endosso' ASC NULLS FIRST, " \
    'carteira_leitura_itens.posicao ASC'
  )

  def initialize(leitura)
    @leitura = leitura
    @account = leitura.account
    @pessoas = Carteira::Conector::PessoaDoRegistro.new(@account)
  end

  # :continua quando sobrou registro para o próximo bloco; :terminou no fim.
  def call
    return :terminou unless @leitura.estado == 'trazendo'

    itens = @leitura.itens.where(estado: LIDO).order(ORDEM).limit(BLOCO).to_a
    ultimos = ultimos_do_mesmo_seguro
    itens.each { |item| ultimos.include?(item.id) ? gravar(item) : item.update!(estado: REPETIDO) }
    @leitura.update!(updated_at: Time.current)
    return :continua if @leitura.itens.exists?(estado: LIDO)

    terminar
    :terminou
  end

  private

  # O id do último registro (na ORDEM) de cada referência e começo de vigência que ainda falta gravar.
  def ultimos_do_mesmo_seguro
    chaves = @leitura.itens.where(estado: LIDO).order(ORDEM)
                     .pluck(:id, Arel.sql("carteira_leitura_itens.campos ->> 'ref'"), Arel.sql("carteira_leitura_itens.campos ->> 'inicio_vigencia'"))
    chaves.group_by { |_id, ref, inicio| [ref, inicio] }.values.to_set { |grupo| grupo.last.first }
  end

  def gravar(item)
    Carteira::Apolice.transaction(requires_new: true) { trazer(item) }
  rescue CustomExceptions::CarteiraRecusa => e
    nao_entrou(item, e.codigo)
  rescue ActiveRecord::RecordInvalid
    nao_entrou(item, 'invalido')
  rescue StandardError => e
    Rails.logger.warn("[carteira][conector][gravar] item=#{item.id} nao_entrou: #{e.class.name}")
    nao_entrou(item, 'falha')
  end

  def trazer(item)
    lido = Carteira::ItemLido.new(item)
    dono = @pessoas.de(lido)
    raise CustomExceptions::CarteiraRecusa.new('sem_pessoa'), cause: nil unless dono

    resultado = guardar(lido, dono)
    return item.update!(estado: IGUAL) if nada_mudou?(resultado)

    Carteira::Renovacao::Ligar.new(resultado.apolice, user: @leitura.user).sozinha if resultado.situacao == Carteira::Guardar::NOVA
    item.update!(estado: 'trazido', apolice: resultado.apolice, contact: dono.pessoa, **campos_depois(lido, dono))
  end

  # `igual` com um passo desta busca no seguro é a origem que subiu (da planilha ou do PDF para o conector): mudou, e liga.
  def nada_mudou?(resultado)
    resultado.situacao == Carteira::Guardar::IGUAL &&
      !resultado.apolice.eventos.exists?(["carteira_apolice_eventos.valores ->> 'leitura' = ?", @leitura.id.to_s])
  end

  def guardar(lido, dono)
    Carteira::Guardar.new(@account, origem: 'conector', user: @leitura.user, leitura: @leitura)
                     .call(lido.dados_da_apolice, contato: dono.pessoa, empresa: dono.empresa, origem_ref: lido.valor('ref'))
  end

  # A pessoa que nasceu agora fica marcada; o e-mail que não foi para ela sai do item, para o Desfazer comparar a ficha
  # com o que a busca deixou de fato.
  def campos_depois(lido, dono)
    return {} unless dono.nova

    valores = { Carteira::ItemLido::PESSOA_NOVA => Time.current.iso8601 }
    valores['segurado_email'] = nil if dono.pessoa.email.blank?
    lido.com(valores)
  end

  def nao_entrou(item, codigo)
    item.update!(estado: 'nao_entrou')
    @leitura.with_lock do
      totais = @leitura.totais.to_h
      @leitura.update!(totais: totais.merge("motivo_#{codigo}" => totais["motivo_#{codigo}"].to_i + 1))
    end
  end

  def terminar
    ligar_as_que_ficaram_sem_anterior
    totais = @leitura.reload.totais.to_h.merge(contagens)
    primeira_trazida = @leitura.totais.to_h.key?(Carteira::Leitura::PRIMEIRA)
    @leitura.update!(estado: 'trazida', confirmada_em: Time.current, totais: totais)
    Carteira::Conector::BuscaDiaria.new(@account).ligar_na_primeira!(@leitura) if primeira_trazida
    Carteira::Conector::PdfsJob.perform_later(@leitura.id)
  end

  def contagens
    trazidos = @leitura.itens.where(estado: 'trazido')
    novas = trazidos.where('carteira_leitura_itens.campos ->> ? IS NOT NULL', Carteira::ItemLido::PESSOA_NOVA)
    { 'seguros' => trazidos.distinct.count(:apolice_id), 'pessoas' => trazidos.distinct.count(:contact_id),
      'pessoas_novas' => novas.distinct.count(:contact_id), 'registros_trazidos' => trazidos.count,
      'nao_entraram' => @leitura.itens.where(estado: 'nao_entrou').count, 'iguais' => @leitura.itens.where(estado: IGUAL).count,
      'substituidos' => @leitura.itens.where(estado: REPETIDO).count }
  end

  # A renovação cuja anterior chegou depois dela na mesma busca (ou sem começo da vigência para ordenar) se liga agora.
  def ligar_as_que_ficaram_sem_anterior
    @leitura.apolices.where(apolice_anterior_id: nil).find_each do |apolice|
      Carteira::Renovacao::Ligar.new(apolice, user: @leitura.user).sozinha
    rescue StandardError => e
      Rails.logger.warn("[carteira][conector][gravar] apolice=#{apolice.id} sem_ligar: #{e.class.name}")
    end
  end
end
