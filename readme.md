To start project you will need
- [ ] [PostgreSQL](https://www.postgresql.org/download/)
- [ ] [Ruby](https://www.ruby-lang.org/en/documentation/installation/)

Then you need to install gems
```bash

gem install 'faraday'
gem install 'json'

gem install 'telegram/bot'
gem install 'openai'

gem install 'dotenv/load'

gem install 'pg'
gem install 'redis'

```

Then you need to create database
```bash
psql -U postgres
CREATE DATABASE "name-of-your-database";
```

Then you need to rename .env.example in .env and set params for your local database

Last thing you will need is to start bot

```bash
ruby bot.rb
```
