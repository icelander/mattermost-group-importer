FROM ruby:3.0.2

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile* ./
RUN bundle install

ADD mattermost.rb .
ADD main.rb .
ADD entrypoint.sh .

VOLUME ["/usr/src/app/conf"]

CMD ["./entrypoint.sh"]