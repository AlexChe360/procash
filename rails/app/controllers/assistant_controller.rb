class AssistantController < ApplicationController
  RATE_STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)
  rate_limit to: 6, within: 1.minute, store: RATE_STORE, with: -> { render json: { error: "Слишком много вопросов. Попробуйте через минуту.", sources: [{ title: "Документация", url: "/documentation" }] }, status: :too_many_requests }
  def create
    return render(json: { error: "Помощник пока отключён.", sources: fallback }, status: :service_unavailable) unless SupportAssistant::Client.enabled?
    question = params[:question]
    unless question.is_a?(String) && (3..600).cover?(question.strip.length) && question.bytesize <= 2400
      return render json: { error: "Введите вопрос от 3 до 600 символов." }, status: :unprocessable_entity
    end
    unless SupportAssistant::KnowledgeBase.on_topic?(question)
      return render json: { answer: SupportAssistant::KnowledgeBase::OUT_OF_SCOPE, sources: fallback }
    end
    if question.strip.match?(/\A(?:что такое|расскажи (?:мне )?(?:о|про))\s+pro\s*cash[?!.\s]*\z/i)
      return render json: { answer: "ProCash — сервис для ресторанов: гость сканирует QR-код на столе и открывает актуальный счёт из кассовой системы. В кабинете можно настроить точки, интеграцию с iiko, QR-карточки и подать заявку на эквайринг. Реальные банковские платежи в текущей версии пока не включены.", sources: fallback }
    end
    sources = SupportAssistant::KnowledgeBase.find(question)
    if sources.empty?
      return render json: { answer: SupportAssistant::KnowledgeBase::OUT_OF_SCOPE, sources: fallback }
    end
    answer = SupportAssistant::Client.new.call(question: question.strip, sources: sources)
    notice = if sources.any? { |source| source[:url].in?(%w[/documentation#acquiring /documentation#payments]) }
      "Основного провайдера можно выбрать только после одобрения ProCash. Реальные банковские платежи пока не включены."
    end
    render json: { answer: answer, notice: notice, sources: sources.map { |item| item.slice(:title, :url) } }
  rescue SupportAssistant::Client::Busy
    render json: { error: "Помощник занят другим вопросом. Попробуйте немного позже.", sources: fallback }, status: :too_many_requests
  rescue SupportAssistant::Client::Unavailable
    render json: { error: "Сейчас помощник недоступен. Ответ можно поискать в документации или обратиться в ProCash.", sources: fallback }, status: :service_unavailable
  end
  private
  # The public widget posts to the same origin it was loaded from, including
  # local development aliases. Rails also verifies its CSRF token and origin.
  def expected_request_origin = request.base_url
  def fallback = [{ title: "Открыть документацию", url: "/documentation" }]
end
