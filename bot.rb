# frozen_string_literal: true

require 'telegram/bot'
require './db'
require 'openai'
require 'dotenv/load'
require 'redis'
require 'byebug'

Telegram::Bot::Client.run(ENV['TOKEN']) do |bot|
  @redis = Redis.new

  def api_key(user_id)
    user = Database.get_user(user_id)
    return nil if user.nil?

    user.values[0][7]
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

  def create_invite_token(user_id)
    Database.create_invite_token(user_id)
  end

  def check_invite_token(token)
    Database.check_token(token).values.any?
  end

  def user_authorized?(user_id)
    user = Database.get_user(user_id)
    return false if user.nil? || Database.user_have_token?(user_id).values.empty? && user.values[0][7].nil?

    true
  end

  def get_user(user_id)
    Database.get_user(user_id)
  end

  def delete_messages(user_id)
    Database.delete_messages(user_id)
  end

  def set_token_owner_and_status(token, user_id)
    Database.set_token_owner_and_status(token, user_id)
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
            content: "Если пользователь запрашивает местоположение географического объекта возвращай ответ ввиде 'location_sender(latitude, longitude)| additional_info', где latitude и longitude это широта и долгота, а additional_info - это весь остальной текст, пример - 'location_sender(55.755826, 37.617300)| Конечно, вот ваша точка'" },
          { role: 'system',
            content: "Если пользователь заправшивает фотографию/изображение чего-либо возвращай ответ ввиде 'image_sender(image_url)| additional_info}', где image_url это ссылка на изображение, а additional_info - это весь остальной текст, пример - 'image_sender(https://i.imgur.com/1Q1Z1Zb.jpg)| Конечно, вот ваша фотография'" }
        ].concat(old_messages << { role: 'user', content: text })
      }
    )

    puts response.dig('choices', 0, 'message', 'content')
    # => "Hello! How may I assist you today?"

    # Получаем ответ от API OpenAI
    puts response.body
    answer = response.dig('choices', 0, 'message', 'content')

    if answer.start_with?('location_sender') || answer.start_with?(' location_sender')
      location_sender(answer.split(',')[0], answer.split(',')[1], bot,
                      message)
      answer = answer.split('|')[1]
    elsif answer.start_with?('image_sender')
      send_photo(bot, message, answer.split(','[0].gsub('image_sender(', '')))
      answer = answer.split('|')[1]
    end
    add_message(message.from.id, answer, 'assistant') unless answer.nil?
    # Отправляем ответ пользователю
    bot.api.send_message(chat_id: message.chat.id, text: answer)
  end

  def enter_user_key(bot, message)
    # Проверяем введённый пользователем ключ
    openai = OpenAI::Client.new(access_token: message.text)
    response = openai.completions(
      parameters: {
        model: 'davinci',
        prompt: 'Hello, I am a chatbot. How are you?',
        max_tokens: 5
      }
    )
    if response.body['error'].nil?
      api_key_update(message.from.id, message.text)
      bot.api.send_message(chat_id: message.chat.id, text: 'Your key is correct! Now you can use this bot.')
      @redis.del(message.from.id)
    else
      bot.api.send_message(chat_id: message.chat.id,
                           text: 'Your key is incorrect! Try again. You can get your key here: https://platform.openai.com/account/api-keys')
    end
  end

  def increase_daily_usage(user_id)
    # Увеличиваем количество использований бота на 1
    Database.increase_daily_usage(user_id)
  end

  def create_invite_token(user_id)
    # Создаём токен для приглашения
    Database.create_token(user_id)
  end

  def add_user(user_id)
    # Добавляем пользователя в базу данных
    Database.add_user(user_id)
  end

  def daily_limit_exceeded?(user_id, bot)
    # Проверяем, не превысил ли пользователь лимит использования бота в день
    daily_limit = Database.get_daily_limit(user_id).values[0][0].to_i
    daily_usage = Database.get_daily_usage(user_id).values[0][0].to_i

    return true if daily_usage >= daily_limit

    show_daily_limit_message(user_id, bot, daily_limit) if daily_usage >= daily_limit - 2

    false
  end

  def get_daily_limit(user_id)
    # Получаем лимит использования бота в день
    Database.get_daily_limit(user_id).values[0][0].to_i
  end

  def show_daily_limit_message(user_id, bot, daily_limit)
    bot.api.send_message(chat_id: user_id,
                         text: "You have last request for today. You can use this bot #{daily_limit} times per day.")
  end

  bot.listen do |message|
    puts message
    puts message.class
    if message.from.is_bot == true || message.instance_of?(Telegram::Bot::Types::Message) && message.text.nil? || message.class != Telegram::Bot::Types::Message && message.class != Telegram::Bot::Types::CallbackQuery
      next
    end

    if message.respond_to? :data
      unless user_authorized?(message.from.id) || message.data == 'enter_your_key'
        bot.api.send_message(chat_id: message.message.chat.id,
                             text: 'Sory, but you are not authorized to use this bot.')
        next
      end
      # Обработка данных, полученных при нажатии кнопок
      if message.data == 'use_my_key'
        api_key_update(message.from.id, ENV['OPENAI_API_KEY']) unless api_key(message.from.id) == ENV['OPENAI_API_KEY']

        bot.api.send_message(chat_id: message.message.chat.id,
                             text: "Great, you've chosen to use our key. Please enter the text you want me to process.")
      elsif message.data == 'enter_your_key'
        bot.api.send_message(chat_id: message.message.chat.id, text: 'Please enter your OpenAI API key.')
        @redis.set(message.from.id, 'enter_your_key')
      else
        bot.api.send_message(chat_id: message.message.chat.id, text: 'Sorry, but I don\'t understand you.')
      end
    elsif message.text.start_with?('/start')
      if message.text.gsub('/start ', '').empty? || message.text.gsub('/start', '').empty?
        if get_user(message.from.id).nil?
          kb = [[
            Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Enter your key', callback_data: 'enter_your_key')
          ]]
          markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
          bot.api.send_message(chat_id: message.chat.id,
                               text: 'To start using the bot, please enter your OpenAI API key. Or get invited to the beta test by someone who has already been invited.', reply_markup: markup)
        else
          bot.api.send_message(chat_id: message.chat.id,
                               text: 'Welcome back! You can use /gpt in public chanels to start using the bot. Or send some text to me directly to start a conversation.')
        end
        next

      elsif check_invite_token(message.text.gsub('/start ', ''))
        bot.api.send_message(chat_id: message.chat.id,
                             text: 'Great! You have been invited to the beta test. You will have 10 free tryes per day, have fun :).')
        add_user(message.from.id)
        set_token_owner_and_status(message.text.gsub('/start ', ''), message.from.id)
      else
        bot.api.send_message(chat_id: message.chat.id, text: 'Sorry, this invite code is invalid.')
        next
      end

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
      enter_user_key(bot, message) if redis.get(message.from.id) == 'enter_your_key'
      next if message.text.empty?

      send_message(bot, message)
    elsif message.text.start_with?('/new_chat')
      unless user_authorized?(message.from.id)
        bot.api.send_message(chat_id: message.chat.id, text: 'Sory, but you are not authorized to use this bot.')
        next
      end
      delete_messages(message.from.id)
    elsif message.text.start_with?('/invite')
      bot.api.send_message(chat_id: message.chat.id,
                           text: "Here is your invite link: #{ENV['BOT_URL']}?start=#{create_invite_token(message.from.id)}")
    else
      if @redis.get(message.from.id) == 'enter_your_key'
        enter_user_key(bot, message)
        next
      end

      unless user_authorized?(message.from.id)
        bot.api.send_message(chat_id: message.chat.id,
                             text: 'Sory, but you are not authorized to use this bot. type /start to add your key. Or get invited to the beta test by someone who has already been invited.')
        next
      end

      if daily_limit_exceeded?(message.from.id, bot)
        bot.api.send_message(chat_id: message.chat.id,
                             text: "Sorry, but you have reached your daily limit of #{get_daily_limit(message.from.id)} requests. You can get more requests by inviting your friends to the beta test.")
        next
      end

      unless message.chat.type == 'private'
        bot.api.send_message(chat_id: message.chat.id,
                             text: 'Я не знаю такой команды :С')
      end

      send_message(bot, message)

      increase_daily_usage(message.from.id)
    end
  end
end
