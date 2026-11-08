# #2519 (frente 1): quantos comentários de cada anúncio estão com o dono, sem ninguém ter agido. É o contrato com o painel
# de Anúncios (#2521): só leitura, lido do banco (nunca da Meta), sem visibilidade por pessoa (comentário não é
# conversa; quem abre o painel já passou pelo gate dele).
#
# Esperando: o que a IA deixou com o dono nos últimos 7 dias (Registro: reclamação, privado recusado ou incerto, já
# tinha o privado, era o caso mas não sai ali, não cuidou) e o que chegou sem cuidado ligado (`no_care`) e a IA não pegou
# depois. Sai da conta quando a pessoa age no comentário pela plataforma (qualquer ação com actor `user`: responder,
# privado, esconder, apagar — no Instagram, InstagramComments e SeusPosts::ComentariosInstagram gravam as quatro).
#
# Limites, ditos no PR:
# - conta a partir do deploy do #2519 (antes dele, o comentário sem cuidado não deixava registro);
# - o anúncio vem no evento do Instagram; no Facebook não vem, e o Cuidar grava o anúncio do cuidado (Cuidar#registrado).
#   Facebook SEM cuidado: nada no banco liga o post ao anúncio, e o painel mostra o total dos insights;
# - só o primeiro nível, como a lista "Esperando você": a resposta dentro de um comentário (#2454) vai sem anúncio;
# - reclamação e "já recebeu" resolvidos na caixa seguem contados até os 7 dias: responder na conversa não grava ação no
#   comentário (a lista "Esperando você" também os mostra);
# - o comentário cujo evento nunca chegou não tem linha: só o "Esperando você" do Painel (que lê a Meta) o mostra;
# - a resposta dada direto no app do Instagram (fora da plataforma) não deixa linha: o comentário segue contado até os
#   7 dias.
module Crm::MetaAds::ComentariosIa::Esperando
  COM_O_DONO = %w[ai_unread kept_for_owner to_you private_reply_failed private_reply_unsure private_reply_already].freeze

  module_function

  # { 'ad_id' => Integer }, com zero para o anúncio sem nada esperando.
  def por_anuncio(account_id, ad_ids)
    ids = Array(ad_ids).map(&:to_s).uniq
    return {} if ids.empty?

    contagem = contar(esperam(account_id).where(ad_id: ids))
    ids.index_with { |id| contagem.fetch(id, 0) }
  end

  # #2519 (3A): os anúncios da conta com algum comentário esperando, { 'ad_id' => Integer }, só os com mais de zero. É o
  # que põe no "Qual post?" o anúncio que saiu do período de Anúncios mas ainda tem comentário com o dono.
  def anuncios_com_espera(account_id)
    contar(esperam(account_id).where.not(ad_id: nil))
  end

  def contar(escopo)
    escopo.group(:ad_id).distinct.count(:comment_id)
  end

  def esperam(account_id)
    da_ia = Crm::MetaAdsCommentAction.where(account_id: account_id, actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR)
                                     .where(at: Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago..)
    sem_cuidado = da_ia.where(action: Crm::MetaAds::ComentariosIa::Registro::SEM_CUIDADO)
                       .where(sem_outra(actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR, action: Crm::MetaAds::ComentariosIa::Registro::LIDO))

    da_ia.where(action: COM_O_DONO).or(sem_cuidado).where(sem_outra(actor: 'user'))
  end

  # NOT EXISTS de outra ação no mesmo comentário (conta, rede e id): o índice idx_crm_meta_ads_comment_actions_lookup.
  def sem_outra(**filtros)
    tabela = Crm::MetaAdsCommentAction.table_name
    outra = Crm::MetaAdsCommentAction.unscoped.from("#{tabela} outra").select('1')
                                     .where("outra.account_id = #{tabela}.account_id AND outra.network = #{tabela}.network " \
                                            "AND outra.comment_id = #{tabela}.comment_id")
    filtros.each { |coluna, valor| outra = outra.where("outra.#{coluna}" => valor) }
    outra.arel.exists.not
  end
end
