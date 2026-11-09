# IA cuida dos comentários (#2212, A2; #2454): o bloco "O que tem nos comentários" do post e do anúncio, antes de o
# dono ligar o cuidado. Só o que o código conta, sem IA (regra do #2436: antes do clique em "Cuidar dos comentários",
# nenhuma chamada de IA):
# - `waiting`: os comentários que esperam o dono (Fonte: de outra pessoa, não escondidos, sem resposta da conta e sem
#   privado); com a flag meta_ads_comentarios_ia, também as respostas de cliente dentro deles (o fio conta,
#   #2454; Fonte.que_esperam), para bater com o número de comentários que a Meta mostra;
# - `private_window`: desses, os que ainda cabem no privado (até Cuidar::JANELA, 7 dias). Sem a data, não cabe.
#
# A leitura é a da Fonte, ao vivo na Meta, como o Painel. Leitura que não ficou pronta devolve só o status dela. No
# anúncio nas duas redes com uma só lida (#2522), os números são os da rede que leu e `network_status` diz qual faltou.
class Crm::MetaAds::ComentariosIa::Resumo
  # alvo: os ids para achar a Fonte de novo (Fonte.do_alvo), quando ela não vem pronta.
  def initialize(account:, alvo:, fonte: nil)
    @account = account
    @alvo = alvo.to_h.stringify_keys
    @fonte = fonte || Crm::MetaAds::ComentariosIa::Fonte.do_alvo(account, @alvo)
  end

  def call
    return { status: 'not_found' } if @fonte.nil?

    lido = @fonte.ler
    return { status: lido[:status] } unless lido[:status] == 'ready'

    linhas = Crm::MetaAds::ComentariosIa::Fonte.que_esperam(@account, lido)
    { status: 'ready', waiting: linhas.size, private_window: linhas.count { |linha| cabe_no_privado?(linha) },
      network_status: lido[:status_das_redes] }.compact
  end

  private

  def cabe_no_privado?(linha)
    linha[:momento].present? && linha[:momento] >= Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago
  end
end
