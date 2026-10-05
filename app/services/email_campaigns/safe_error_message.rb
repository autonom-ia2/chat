# Error text that may reach last_error or the logs (#999 review M1): e-mail addresses become
# <EMAIL> (any space-separated word with an "@"), then CampaignImports::SafeLogMessage masks
# long tokens and digit runs and caps the length. Database errors quote the conflicting row, so
# they must never be stored as they come.
module EmailCampaigns::SafeErrorMessage
  EMAIL_MASK = '<EMAIL>'.freeze

  def self.call(message)
    words = message.to_s.split.map { |word| word.include?('@') ? EMAIL_MASK : word }
    CampaignImports::SafeLogMessage.call(words.join(' '))
  end
end
