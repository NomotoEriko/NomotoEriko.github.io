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
    @edit_file = false
  end

  after do
    if @edit_file
      Thread.new do
        @@m.synchronize do
          update_and_commit
        end
      end
    end
  end

  @@logger = Logger.new('/tmp/sample-app.log')
  @@m = Thread::Mutex.new
  @edit_file = false
  @data = nil

  get '/' do
    'OK'
  end

  post '/add' do
    return {
      response_type: 'ephemeral',
      text: '処理中です。少し時間をおいて再度お試しください。'
    }.to_json if @@m.locked?
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

    branch = Time.now.strftime('created-by-app-%Y-%m-%d-%H-%M')
    @data = {
      type: type,
      title: title,
      author: author,
      trigger: trigger,
      impression: impression,
      date: date,
      branch: branch
    }
    uri = git_client.remote.url.split('@').last
    path = "#{uri.slice(0, uri.length - 4)}/tree/#{branch}"
    @edit_file = true

    return {
      response_type: 'in_channel',
      text: [type, title, author, date, trigger, impression, '', "created branch #{path}"].join("\n")
    }.to_json
  end

  def update_and_commit
    git_client.checkout('master')
    git_client.pull

    new_elem = [
      '<tr>',
      '  <td class="short">' + @data[:title] + '</td>',
      '  <td class="short">' + @data[:author] + '</td>',
      '  <td class="short">' + @data[:date] + '</td>',
      '  <td class="long">' + @data[:trigger] + '</td>',
      '  <td class="long">' + @data[:impression] + '</td>',
      '</tr>'
    ].join("\n")

    git_client.branch(@data[:branch]).checkout
    content = File.readlines(File.join('dist', "#{@data[:type]}.html"))
    index = content.find_index do |line|
      line.match?(/\<\/tr\>/)
    end + 1
    File.open(File.join('dist', "#{@data[:type]}.html"), 'w') do |f|
      f.write([content.take(index), new_elem, content.last(content.length - index)].flatten.join)
    end

    git_client.add
    git_client.commit(git_client.current_branch)
    git_client.push(remote="origin", branch=git_client.current_branch)
    git_client.checkout('master')
    @edit_file = false
  end

  def git_client
    @git_client ||= File.exist?('dist') ? Git.open('dist', :log => @@logger) : clone
  end

  def clone
    g = Git.clone(ENV['GIT_REPOSITORY_URI'], 'dist', :log => @@logger)
    g.config('user.name', ENV['GIT_USER_NAME'])
    g.config('user.email', ENV['GIT_USER_EMAIL'])
    g
  end
end
