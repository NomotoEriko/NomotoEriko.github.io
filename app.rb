require 'sinatra/base'
require 'logger'
require 'json'

require 'git'

# bundle exec rackup -o 0.0.0.0
# zip ../app.zip -r * .[^.gD]*

class App < Sinatra::Base
  set :logging, true
  set :public_folder, 'public'

  before do
    content_type :json
    @@git_client = File.exist?('dist') ? Git.open('dist', :log => @@logger) : clone
    @@git_client.checkout('master')
    @@git_client.pull
  end

  after do
    if @@git_client.current_branch != 'master'
      @@git_client.add
      @@git_client.commit(@@git_client.current_branch)
      @@git_client.push(remote="origin", branch=@@git_client.current_branch)
      @@git_client.checkout('master')
    end
  end

  @@logger = Logger.new('/tmp/sample-app.log')

  get '/' do
    'OK'
  end

  post '/add' do
    data = URI.decode_www_form(request.body.read).to_h
    text_data = data['text']&.split
    return {
      response_type: 'ephemeral',
      text: '「type タイトル 監督 きっかけ 感想」の形式で入力してください。'
    }.to_json unless text_data&.length == 5
    type, title, author, trigger, impression = text_data
    return {
      response_type: 'ephemeral',
      text: 'type は book film anime のみ有効です。'
    }.to_json unless %w(book film anime).include?(type)
    date = Time.now.strftime('%Y.%m.%d')

    new_elem = [
      '<tr>',
      '  <td class="short">' + title + '</td>',
      '  <td class="short">' + author + '</td>',
      '  <td class="short">' + date + '</td>',
      '  <td class="long">' + trigger + '</td>',
      '  <td class="long">' + impression + '</td>',
      '</tr>'
    ].join("\n")

    path = commit do
      content = File.readlines(File.join('dist', "#{type}.html"))
      index = content.find_index do |line|
        line.match?(/\<\/tr\>/)
      end + 1
      File.open(File.join('dist', "#{type}.html"), 'w') do |f|
        f.write([content.take(index), new_elem, content.last(content.length - index)].flatten.join)
      end
    end

    return {
      response_type: 'in_channel',
      text: [type, title, author, date, trigger, impression, '', "created branch #{path}"].join("\n")
    }.to_json
  end

  def commit(&block)
    name = Time.now.strftime('created-by-app-%Y-%m-%d-%H-%M')
    @@git_client.branch(name).checkout
    block.call
    uri = @@git_client.remote.url.split('@').last
    "#{uri.slice(0, uri.length - 4)}/tree/#{name}"
  end

  def clone
    g = Git.clone(ENV['GIT_REPOSITORY_URI'], 'dist', :log => @@logger)
    g.config('user.name', ENV['GIT_USER_NAME'])
    g.config('user.email', ENV['GIT_USER_EMAIL'])
    g
  end
end
