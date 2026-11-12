module SupportAssistant
  class KnowledgeBase
    OUT_OF_SCOPE = "Я помощник только по сервису ProCash. Могу подсказать, как настроить кабинет, подключить кассу, оформить QR-коды, чаевые и эквайринг. Задайте вопрос о ProCash.".freeze
    TOPIC = /procash|про\s*к[эе]ш|iiko|айко|икко|ийко|qr|куар|кюар|эквайр|freedom|merchant\s*id|провайдер|чаев|касс|кабинет|торгов.*точк|стол|сч[её]т|транзакц|плат[её]ж|оплат|парол|приглашен|логотип|бин|иин/i
    UNRELATED = /погод|гороскоп|анекдот|стих|сочинен|рецепт|футбол|политик|президент|криптовалют|биткоин|столиц|переведи|перевод.*текст|напиши.*(?:код|программ)|реши.*(?:задач|уравнен)|игнорируй|забудь.*инструкц|смени.*рол/i
    def self.on_topic?(question)
      question.match?(TOPIC) && !question.match?(UNRELATED)
    end
    STOP = %w[как что где мне это для или при уже ещё еще надо можно нужно меня моего моего почему когда пожалуйста].freeze
    EXTRA = {
      id: "troubleshooting", title: "Если счёт не открывается по QR",
      intro: "Если заказа нет: проверьте организацию, терминальную группу и привязку стола. Изменение ключа, организации или сопоставлений выключает интеграцию: повторите проверку готовности и активацию. Если заказ открыт на редактирование в iikoFront, сохраните изменения и выйдите к схеме зала, затем обновите QR. Не закрывайте и не оплачивайте заказ ради синхронизации. «Получаем счёт» означает синхронизацию: подождите и обновите страницу. Если ошибка сохраняется, обратитесь в ProCash."
    }.freeze
    def self.find(question)
      return [] unless on_topic?(question)
      query = question.downcase
      query += " iiko касса" if query.match?(/айко|икко|ийко/)
      query += " qr счёт" if query.match?(/куар|кюар|qr|нет заказ|не вид.*заказ/)
      terms = query.scan(/[[:alnum:]]+/).reject { |word| word.length < 3 || STOP.include?(word) }.map { |word| word[0, 5] }.uniq
      candidates = MerchantGuide::SECTIONS + [EXTRA]
      if query.match?(/эквайр|freedom|провайдер|merchant\s*id/)
        candidates = candidates.select { |section| section[:id].in?(%w[acquiring payments]) }
      elsif query.match?(/iiko|икко|айко|ийко/)
        candidates = candidates.select { |section| section[:id].in?(%w[iiko tables troubleshooting]) }
      elsif query.match?(/парол/)
        candidates = candidates.select { |section| section[:id].in?(%w[access settings]) }
      elsif query.match?(/чаев/)
        candidates = candidates.select { |section| section[:id] == "tips" }
      end
      candidates.filter_map do |section|
        body = [section[:intro], *Array(section[:steps]).map { |title, text| "#{title}: #{text}" }, section[:note]].compact.join("\n")
        score = terms.sum { |term| (section[:title].downcase.include?(term) ? 5 : 0) + (body.downcase.include?(term) ? 1 : 0) }
        next unless score.positive?
        [score, { title: section[:title], url: "/documentation##{section[:id]}", text: body[0, 2100] }]
      end.sort_by { |score, _| -score }.then { |ranked| ranked.first(2).select { |score, _| score >= [ranked.first&.first.to_i / 2.0, 1].max } }.map(&:last)
    end
  end
end
