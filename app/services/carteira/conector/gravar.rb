# A gravação de uma busca no conector (E7, #2900), no Carteira::Conector::GravarJob: cada registro pronto vira seguro na
# carteira, BLOCO por execução (o job se reagenda até acabar). A primeira busca chega aqui pelo "Trazer" do Conferir; a de
# todo dia, sozinha.
#
# Para cada registro, na ordem em que chegou (o endosso vem depois da apólice, e atualiza a mesma), numa transação só dele:
# 1. a pessoa (Carteira::Conector::PessoaDoRegistro): a do seguro que já tem a mesma referência; senão, a da conta que tem
#    o CPF/CNPJ do segurado (decisão R1); senão, a que nasce agora com o nome do segurado. Nunca pelo nome. A que nasce
#    fica marcada no item (o Desfazer só tira quem a busca criou) e não leva o e-mail que já é de outra pessoa da conta;
# 2. o seguro, SEMPRE pelo gravador único (Carteira::Guardar, origem `conector`, a mais forte, com a leitura e com
#    `origem_ref` = a referência do registro). A mesma referência de novo atualiza, nunca duplica;
# 3. o seguro novo pode ser a renovação de um que já estava na carteira (feita fora do sistema): ele se liga ao anterior
#    pelo caminho de sempre (Carteira::Renovacao::Ligar#sozinha), e o card de renovação do anterior fecha.
# O registro sem pessoa (sem documento e sem seguro guardado com a referência), recusado pelo gravador ou com um erro
# inesperado vira `nao_entrou` (o motivo é só contado) e os outros seguem.
#
# No fim a leitura fica `trazida`, com quantos seguros e quantas pessoas entraram; os PDFs vêm depois, num job próprio
# (Carteira::Conector::PdfsJob). Rodar de novo continua de onde parou. Nada daqui vai para log além de ids.
class Carteira::Conector::Gravar
  BLOCO = 100
  LIDO = Carteira::Conector::Ler::LIDO

  def initialize(leitura)
    @leitura = leitura
    @account = leitura.account
    @pessoas = Carteira::Conector::PessoaDoRegistro.new(@account)
  end

  # :continua quando sobrou registro para o próximo bloco; :terminou no fim.
  def call
    return :terminou unless @leitura.estado == 'trazendo'

    itens = @leitura.itens.where(estado: LIDO).order(:posicao).limit(BLOCO).to_a
    itens.each { |item| gravar(item) }
    @leitura.update!(updated_at: Time.current)
    return :continua if @leitura.itens.exists?(estado: LIDO)

    terminar
    :terminou
  end

  private

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
    Carteira::Renovacao::Ligar.new(resultado.apolice, user: @leitura.user).sozinha if resultado.situacao == Carteira::Guardar::NOVA
    item.update!(estado: 'trazido', apolice: resultado.apolice, contact: dono.pessoa, **campos_depois(lido, dono))
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
    trazidos = @leitura.itens.where(estado: 'trazido')
    novas = trazidos.where('carteira_leitura_itens.campos ->> ? IS NOT NULL', Carteira::ItemLido::PESSOA_NOVA)
    totais = @leitura.reload.totais.to_h.merge(
      'seguros' => trazidos.distinct.count(:apolice_id), 'pessoas' => trazidos.distinct.count(:contact_id),
      'pessoas_novas' => novas.distinct.count(:contact_id), 'nao_entraram' => @leitura.itens.where(estado: 'nao_entrou').count
    )
    primeira_trazida = @leitura.totais.to_h.key?(Carteira::Leitura::PRIMEIRA)
    @leitura.update!(estado: 'trazida', confirmada_em: Time.current, totais: totais)
    Carteira::Conector::BuscaDiaria.new(@account).ligar_na_primeira!(@leitura) if primeira_trazida
    Carteira::Conector::PdfsJob.perform_later(@leitura.id)
  end
end
