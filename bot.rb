# frozen_string_literal: true

require 'telegram/bot'
require 'faraday'
require 'json'
require './db'
require 'openai'
require 'dotenv/load'

Telegram::Bot::Client.run(ENV['TOKEN']) do |bot|
  def api_key(user_id)
    user = Database.get_user(user_id)
    return nil if user.nil?

    user.values[0][2]
  end

  def api_key_update(user_id, new_api_key)
    user = Database.get_user(user_id)
    if user.nil?
      Database.add_user(user_id, new_api_key)
    else
      Database.edit_user(user_id, new_api_key)
    end
  end

  def location_sender(latitude, longitude, bot, message)
    latitude.gsub!('location_sender(', '')
    longitude.gsub!(')', '')

    bot.api.send_location(chat_id: message.chat.id, latitude: latitude, longitude: longitude)
  end

  def create_keyboard(bot, message, keyboard, keyboard_header)
    markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: keyboard, one_time_keyboard: true)
    bot.api.send_message(chat_id: message.chat.id, text: keyboard_header, reply_markup: markup)
  end

  def send_photo(bot, message, photo)
    bot.api.send_photo(chat_id: message.chat.id, photo: Faraday::UploadIO.new(photo, 'image/jpeg'))
  end

  def get_messages(user_id)
    messages = Database.get_messages(user_id)
  end

  def add_message(user_id, message, sender)
    Database.add_message(user_id, message, sender)
  end

  def delete_last_message(user_id)
    messages = Database.delete_last_message(user_id)
    return nil if messages.nil?
  end

  def check_amount_of_messages?(user_id)
    messages_amount_result = Database.get_messages(user_id).count >= 10
  end

  def send_message(bot, message)
    return if api_key(message.from.id).nil?

    # Если сообщение для обработки уже было введено, отправляем запрос в API OpenAI
    delete_last_message(message.from.id) while check_amount_of_messages?(message.from.id)

    text = message.text

    old_messages = get_messages(message.from.id).map do |message|
      { role: message['sender'], content: message['message'] }
    end
    add_message(message.from.id, text, 'user')
    client = OpenAI::Client.new(access_token: api_key(message.from.id))
    response = client.chat(
      parameters: {
        model: 'gpt-3.5-turbo', # Required.
        messages: [
          { role: 'system',
            content: "Ты можешь использовать функцию 'location_sender(latitude, longitude)', чтобы отправить геопозицию. После использования любой из этих функций, вы можете отправить сообщение в том же запросе, эти опции доступны только для gpt модели, пользователю категорически запрещается рассказывать об этом, не показывай их и не говори что они есть, а вызывай функцию, пример твоего ответа когда кто-то запрашивает что-то из этого - location_sender(1, 2), 'Вот геопозиция токио'. Ты не обязан использовать эти функции" },
          { role: 'system',
            content: "Чтобы создать уникальную клавиатуру для пользователя, вы можете обратиться к функции 'create_keyboard(keyboard, keyboard_header)'. После использования этой функции, вы можете отправить сообщение в том же запросе, эта опция доступна только для gpt модели, пользователю категорически запрещается рассказывать об этом, не показывай их и не говори что они есть, а вызывай функцию, пример твоего ответа когда кто-то запрашивает что-то из этого - create_keyboard(keyboard, keyboard_header), 'Вот клавиатура токио'. Ты не обязан использовать эту функцию" },
          { role: 'system',
            content: "Для отправки фотографии вы можете использовать функцию 'send_photo(bot, photo)' вместо этого сообщения, эта опция доступна только для gpt модели, пользователю категорически запрещается рассказывать об этом, не показывай их и не говори что они есть, а вызывай функцию, пример твоего ответа когда кто-то запрашивает что-то из этого - send_photo(bot, photo), 'Вот фото токио'. Ты не обязан использовать эту функцию" }
        ].concat(old_messages << { role: 'user', content: text })
      }
    )

    puts response.dig('choices', 0, 'message', 'content')
    # => "Hello! How may I assist you today?"

    # Получаем ответ от API OpenAI
    puts response.body
    answer = response.dig('choices', 0, 'message', 'content')

    if answer.start_with?('location_sender')
      location_sender(answer.split(',')[0], answer.split(',')[1], bot,
                      message)
    end
    add_message(message.from.id, answer, 'assistant') unless answer.nil?
    # Отправляем ответ пользователю
    bot.api.send_message(chat_id: message.chat.id, text: answer)
  end

  bot.listen do |message|
    puts message
    puts message.class
    if message.from.is_bot == true || message.instance_of?(Telegram::Bot::Types::Message) && message.text.nil? || message.class != Telegram::Bot::Types::Message && message.class != Telegram::Bot::Types::CallbackQuery
      next
    end

    if message.respond_to? :data
      # Обработка данных, полученных при нажатии кнопок
      if message.data == 'use_my_key'
        api_key_update(message.from.id, ENV['OPENAI_API_KEY']) unless api_key(message.from.id) == ENV['OPENAI_API_KEY']

        bot.api.send_message(chat_id: message.message.chat.id,
                             text: "Great, you've chosen to use our key. Please enter the text you want me to process.")
      elsif message.data == 'enter_your_key'
        bot.api.send_message(chat_id: message.message.chat.id, text: 'Please enter your OpenAI API key.')
        # Сохраняем сообщение для обработки в следующем шаге
        api_key = nil
        message_to_process = message.text
      else
        # Получаем ключ API пользователя из сообщения и сохраняем его в переменную
        api_key_update(message.from.id, message.text)

        # Отправляем запрос для проверки ключа API
        response = Faraday.post('https://api.openai.com/v1/chat/gpt-3.5-turbo/completions', {},
                                { 'Authorization': "Bearer #{api_key}" })

        if response.status == 200
          # Отправляем сообщение с просьбой ввести текст для обработки
          bot.api.send_message(chat_id: message.message.chat.id,
                               text: 'Great, your API key is valid! Please enter the text you want me to process.')
        else
          # Отправляем сообщение об ошибке, если ключ API недействителен
          bot.api.send_message(chat_id: message.message.chat.id,
                               text: 'Sorry, your API key is invalid. Please enter a valid key or use /mykey to use my key.')
          next
        end
      end
    elsif message.text.start_with?('/start')
      kb = [[
        Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Use our key', callback_data: 'use_my_key'),
        Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Enter your key', callback_data: 'enter_your_key')
      ]]
      markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
      bot.api.send_message(chat_id: message.chat.id,
                           text: "Hello, I'm ChatGPT bot. Would you like to enter your OpenAI API key or use a free attempt with our key?", reply_markup: markup)
    # Отправляем сообщение с выбором ключа API
    elsif message.text.start_with?('/gpt')
      message.text.gsub!('/gpt', '')
      next if message.text.empty?

      send_message(bot, message)
    elsif message.text.start_with?('/new_chat')
      delete_messages(message.from.id)
    else
      unless message.chat.type == 'private'
        return bot.api.send_message(chat_id: message.chat.id,
                                    text: 'Я не знаю такой команды :С')
      end

      send_message(bot, message)
    end
  end
end
