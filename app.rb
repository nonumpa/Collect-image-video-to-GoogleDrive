# app.rb
require 'sinatra'
require 'line/bot'
require './query.rb'
require 'sinatra/reloader' if development?

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text

        p event if event['source']['type'] == 'user' # Don't log group messages

        search_result = query_elastic_search(event.message['text'])

        if search_result.length == 0
          search_result = query_google(event.message['text'])
        end

        if search_result.length > 0
          client.reply_message(event['replyToken'], [
            textmsg("我的朋友，下面幾篇訊息，與您分享 :)")
          ].concat(search_result[0..3].map {|item| textmsg("【#{item[:title]}】#{item[:snippet]} #{item.has_key?(:relevance) ? "（相關指數：#{(100 * item[:relevance]).round} %）" : ''} —— #{item[:url]}") }))
        elsif event['source']['type'] == 'user' # Don't reply empty prompt when in group
          client.reply_message(event['replyToken'], textmsg("找不太到與這則訊息相關的澄清文章唷！"))
        end
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        response = client.get_message_content(event.message['id'])
        p event
        p response

        tf = Tempfile.open("content")
        tf.write(response.body)
      end
    end
  }

  "OK"
end

def textmsg text
  {
    type: 'text',
    text: text
  }
end