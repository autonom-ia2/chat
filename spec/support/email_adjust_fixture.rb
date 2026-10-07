# E-mail on the screen used by the "Ajustar com IA" specs (#1095): a hero with a button, a FAQ block and the
# locked footer. Passes the AI checks of EmailCampaigns::QualityGate.
module EmailAdjustFixture
  FONT = 'font-family="Arial, Helvetica, sans-serif"'.freeze
  HERO = '<mj-section background-color="#ffffff" padding="32px 24px"><mj-column>' \
         "<mj-text #{FONT} font-size=\"28px\" color=\"#1f2937\">Promoção de outubro</mj-text>" \
         "<mj-button #{FONT} font-size=\"16px\" line-height=\"20px\" inner-padding=\"14px 36px\" " \
         'background-color="#0f766e" color="#ffffff" href="https://loja.com.br">Comprar</mj-button>' \
         '</mj-column></mj-section>'.freeze
  FAQ = '<mj-section background-color="#f4f4f4" padding="24px"><mj-column>' \
        "<mj-text #{FONT} font-size=\"16px\" color=\"#1f2937\">Perguntas frequentes, {{ nome }}</mj-text>" \
        '</mj-column></mj-section>'.freeze

  def adjust_base_mjml
    "<mjml><mj-body>#{HERO}#{FAQ}#{EmailCampaigns::LockedFooter::MJML}</mj-body></mjml>"
  end

  def adjust_hero(title: 'Promoção de outubro', button_color: '#0f766e', text_color: '#ffffff')
    colors = %(background-color="#{button_color}" color="#{text_color}")
    HERO.sub('Promoção de outubro', title).sub('background-color="#0f766e" color="#ffffff"', colors)
  end
end
