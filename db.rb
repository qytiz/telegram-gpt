# frozen_string_literal: true

require 'pg'
require 'dotenv/load'

class Database
  @conn = PG.connect(dbname: ENV['DATABASE_NAME'], port: ENV['DATABASE_PORT'], host: ENV['DATABASE_HOST'],
                     password: ENV['DATABASE_PASSWORD'])

  @conn.exec("CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE,
    dayly_usage INTEGER DEFAULT 0,
    dayly_limit INTEGER DEFAULT 10,
    users_invited INTEGER,
    tokens_created INTEGER,
    status TEXT,
    api_key TEXT
  );")

  @conn.exec("CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    sender TEXT,
    user_id INTEGER,
    message TEXT,
    FOREIGN KEY (user_id) REFERENCES users (user_id)
    );")

  @conn.exec("CREATE TABLE IF NOT EXISTS invite_tokens (
    id SERIAL PRIMARY KEY,
    token TEXT UNIQUE,
    invited_user_id INTEGER,
    user_id INTEGER,
    used BOOLEAN DEFAULT false,
    FOREIGN KEY (user_id) REFERENCES users (user_id)
    );")

  class << self
    def add_user(user_id, api_key = ENV['OPENAI_API_KEY'])
      return if user_existed?(user_id).values.any?

      @conn.exec_params('INSERT INTO users (user_id, api_key) VALUES ($1, $2)', [user_id, api_key])
    end

    def all_users
      @conn.exec('SELECT * FROM users')
    end

    def user_existed?(user_id)
      @conn.exec('SELECT * FROM users WHERE user_id = $1', [user_id])
    end

    def get_user(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('SELECT * FROM users WHERE user_id = $1', [user_id])
    end

    def edit_user(user_id, api_key)
      return unless user_existed?(user_id).values.any?

      @conn.exec_params('UPDATE users SET api_key = $1, WHERE user_id = $2', [api_key, user_id])
    end

    def delete_user(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('DELETE FROM users WHERE user_id = $1', [user_id])
    end

    def add_message(user_id, message, sender)
      return unless user_existed?(user_id).values.any?

      @conn.exec_params('INSERT INTO messages (user_id, message, sender) VALUES ($1, $2, $3)',
                        [user_id, message, sender])
    end

    def all_messages
      @conn.exec('SELECT * FROM messages')
    end

    def get_messages(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('SELECT * FROM messages WHERE user_id = $1', [user_id])
    end

    def delete_messages(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('DELETE FROM messages WHERE user_id = $1', [user_id])
    end

    def delete_last_message(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec("DELETE FROM messages
            WHERE id = (  SELECT id FROM messages   WHERE user_id = $1   ORDER BY id DESC   LIMIT 1)", [user_id])
    end

    def increase_daily_usage(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('UPDATE users SET dayly_usage = dayly_usage + 1 WHERE user_id = $1', [user_id])
    end

    def get_daily_usage(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('SELECT dayly_usage FROM users WHERE user_id = $1', [user_id])
    end

    def reset_daily_usage(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('UPDATE users SET dayly_usage = 0 WHERE user_id = $1', [user_id])
    end

    def set_daily_limit(user_id, limit)
      return unless user_existed?(user_id).values.any?

      @conn.exec_params('UPDATE users SET dayly_limit = $1 WHERE user_id = $2', [limit, user_id])
    end

    def get_daily_limit(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('SELECT dayly_limit FROM users WHERE user_id = $1', [user_id])
    end

    def increase_users_invited(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('UPDATE users SET users_invited = users_invited + 1 WHERE user_id = $1', [user_id])
    end

    def get_users_invited(user_id)
      return unless user_existed?(user_id).values.any?

      @conn.exec('SELECT users_invited FROM users WHERE user_id = $1', [user_id])
    end

    def create_token(user_id)
      token = SecureRandom.hex(10)
      @conn.exec_params('INSERT INTO invite_tokens (token, user_id) VALUES ($1, $2)', [token, user_id])
      token
    end

    def check_token(token)
      @conn.exec_params('SELECT * FROM invite_tokens WHERE token = $1 AND used=false', [token])
    end

    def user_have_token?(user_id)
      @conn.exec('SELECT * FROM invite_tokens WHERE invited_user_id = $1', [user_id])
    end

    def set_token_owner_and_status(token, user_id)
      @conn.exec_params('UPDATE invite_tokens SET invited_user_id = $1, used = true WHERE token = $2',
                        [user_id, token])
    end
  end
end
