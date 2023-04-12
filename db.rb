require 'pg'
require 'byebug'

class Database


  @conn.exec("CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE,
    api_key TEXT
  );")

  @conn.exec("CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    sender TEXT,
    user_id INTEGER,
    message TEXT,
    FOREIGN KEY (user_id) REFERENCES users (user_id)
    );")

  class << self
    def add_user(user_id, api_key)
      return if user_existed?(user_id).values.any?
      @conn.exec_params("INSERT INTO users (user_id, api_key) VALUES ($1, $2);", [user_id, api_key])
    end


    def all_users
      @conn.exec("SELECT * FROM users;")
    end

    def user_existed?(user_id)
      @conn.exec("SELECT * FROM users WHERE user_id = $1;", [user_id])
    end

    def get_user(user_id)
      return unless user_existed?(user_id).values.any?
      @conn.exec("SELECT * FROM users WHERE user_id = $1;", [user_id])
    end

    def edit_user(user_id, api_key)
      return unless user_existed?(user_id).values.any?
      @conn.exec_params("UPDATE users SET api_key = $1, WHERE user_id = $2;", [api_key, user_id])
    end

    def delete_user(user_id)
      return unless user_existed?(user_id).values.any?
      @conn.exec("DELETE FROM users WHERE user_id = $1;", [user_id])
    end

    def add_message(user_id, message, sender)
      return unless user_existed?(user_id).values.any?
      @conn.exec_params("INSERT INTO messages (user_id, message, sender) VALUES ($1, $2, $3);", [user_id, message, sender])
    end

    def all_messages
      @conn.exec("SELECT * FROM messages;")
    end

    def get_messages(user_id)
      return unless user_existed?(user_id).values.any?
      @conn.exec("SELECT * FROM messages WHERE user_id = $1;", [user_id])
    end

    def delete_messages(user_id)
        return unless user_existed?(user_id).values.any?
        @conn.exec("DELETE FROM messages WHERE user_id = $1;", [user_id])
    end

    def delete_last_message(user_id)
        return unless user_existed?(user_id).values.any?
        @conn.exec("DELETE FROM messages 
            WHERE id = (  SELECT id FROM messages   WHERE user_id = $1   ORDER BY id DESC   LIMIT 1);", [user_id])
    end
end
end
